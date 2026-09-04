#!/usr/bin/env bash
# lib/detect.sh - locate the running VS Code-family editor and derive its paths.
# Requires lib/log.sh to already be sourced (uses log_error/log_warn).

_proc_exe_path() {
    readlink -f "/proc/$1/exe" 2>/dev/null
}

_proc_parent_pid() {
    local stat
    stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
    stat="${stat##*)}"
    local fields=($stat)
    echo "${fields[1]}"
}

find_electron_ancestor() {
    # Walks the whole ancestor chain (not just to the first hit) and keeps the
    # topmost PID matching product.json, since the closest match is often an
    # intermediate process (e.g. the pty host for the integrated terminal)
    # rather than the editor's actual root/main process.
    local pid="$1" max_hops="${2:-30}" hop=0 exe app_root
    local match_pid="" match_exe=""
    while [[ "$pid" -gt 1 && "$hop" -lt "$max_hops" ]]; do
        exe="$(_proc_exe_path "$pid")"
        if [[ -n "$exe" ]]; then
            app_root="$(dirname "$exe")"
            if [[ -f "$app_root/resources/app/product.json" ]]; then
                match_pid="$pid"
                match_exe="$exe"
            fi
        fi
        pid="$(_proc_parent_pid "$pid")" || break
        [[ -z "$pid" ]] && break
        hop=$((hop + 1))
    done
    if [[ -n "$match_pid" ]]; then
        echo "$match_pid $match_exe"
        return 0
    fi
    return 1
}

_config_dir_candidates() {
    # $1 must be product.json's nameShort (e.g. "Code"), which is what
    # Electron's userData path (and thus the User/settings.json directory)
    # is actually named after - NOT dataFolderName (e.g. ".vscode"), which
    # only names the unrelated CLI data folder used for extensions/argv.json.
    local name_short="$1"

    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        echo "$XDG_CONFIG_HOME/$name_short/User"
    fi
    echo "$HOME/.config/$name_short/User"

    local dir
    for dir in "$HOME"/.var/app/*/config/"$name_short"/User; do
        [[ -d "$dir" ]] && echo "$dir"
    done
    for dir in "$HOME"/snap/*/current/.config/"$name_short"/User; do
        [[ -d "$dir" ]] && echo "$dir"
    done
}

read_product_json() {
    python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        d = json.load(f)
except (OSError, json.JSONDecodeError) as exc:
    print(f'error: failed to read {sys.argv[1]}: {exc}', file=sys.stderr)
    sys.exit(1)
print(d.get('applicationName', ''))
print(d.get('nameShort', ''))
" "$1"
}

resolve_editor_paths() {
    local start_pid="${1:-$PPID}"
    EDITOR_APP_NAME=""
    EDITOR_BIN=""
    EDITOR_CONFIG_DIR=""
    EDITOR_PID=""

    if [[ -z "${TERM_PROGRAM:-}" ]]; then
        log_error "TERM_PROGRAM not set - run this script from inside the editor's integrated terminal"
        return 1
    fi

    local exe app_root product_json product_info app_name name_short pid_and_exe
    pid_and_exe="$(find_electron_ancestor "$start_pid")"
    if [[ -z "$pid_and_exe" ]]; then
        log_error "could not locate the editor process in the process tree"
        return 1
    fi
    EDITOR_PID="${pid_and_exe%% *}"
    exe="${pid_and_exe#* }"

    app_root="$(dirname "$exe")"
    product_json="$app_root/resources/app/product.json"

    product_info="$(read_product_json "$product_json")" || {
        log_error "failed to read product.json at $product_json"
        return 1
    }
    app_name="$(sed -n '1p' <<<"$product_info")"
    name_short="$(sed -n '2p' <<<"$product_info")"

    if [[ -z "$app_name" ]]; then
        log_error "product.json at $product_json has no applicationName"
        return 1
    fi

    if [[ "$app_name" != "$TERM_PROGRAM" ]]; then
        log_warn "applicationName ($app_name) differs from TERM_PROGRAM ($TERM_PROGRAM) - proceeding with $app_name"
    fi

    EDITOR_APP_NAME="$app_name"

    if [[ -x "$app_root/bin/$app_name" ]]; then
        EDITOR_BIN="$app_root/bin/$app_name"
    elif command -v "$app_name" >/dev/null 2>&1; then
        EDITOR_BIN="$(command -v "$app_name")"
        log_warn "using $EDITOR_BIN from PATH (layout $app_root/bin/$app_name not found)"
    else
        log_error "could not find the editor's CLI binary (tried $app_root/bin/$app_name and PATH)"
    fi

    if [[ -n "$name_short" ]]; then
        local candidate found_existing=""
        while IFS= read -r candidate; do
            if [[ -d "$candidate" ]]; then
                EDITOR_CONFIG_DIR="$candidate"
                found_existing="1"
                break
            fi
        done < <(_config_dir_candidates "$name_short")

        if [[ -z "$found_existing" ]]; then
            EDITOR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$name_short/User"
        else
            log_info "using config directory: $EDITOR_CONFIG_DIR"
        fi
    else
        log_warn "product.json has no nameShort - settings/keybindings will be skipped"
    fi

    return 0
}
