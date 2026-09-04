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
    local pid="$1" max_hops="${2:-20}" hop=0 exe app_root
    while [[ "$pid" -gt 1 && "$hop" -lt "$max_hops" ]]; do
        exe="$(_proc_exe_path "$pid")"
        if [[ -n "$exe" ]]; then
            app_root="$(dirname "$exe")"
            if [[ -f "$app_root/resources/app/product.json" ]]; then
                echo "$exe"
                return 0
            fi
        fi
        pid="$(_proc_parent_pid "$pid")" || return 1
        [[ -z "$pid" ]] && return 1
        hop=$((hop + 1))
    done
    return 1
}

_config_dir_candidates() {
    local data_folder="$1"

    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        echo "$XDG_CONFIG_HOME/$data_folder/User"
    fi
    echo "$HOME/.config/$data_folder/User"

    local dir
    for dir in "$HOME"/.var/app/*/config/"$data_folder"/User; do
        [[ -d "$dir" ]] && echo "$dir"
    done
    for dir in "$HOME"/snap/*/current/.config/"$data_folder"/User; do
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
print(d.get('dataFolderName', ''))
" "$1"
}

resolve_editor_paths() {
    local start_pid="${1:-$PPID}"
    EDITOR_APP_NAME=""
    EDITOR_BIN=""
    EDITOR_CONFIG_DIR=""

    if [[ -z "${TERM_PROGRAM:-}" ]]; then
        log_error "TERM_PROGRAM not set - run this script from inside the editor's integrated terminal"
        return 1
    fi

    local exe app_root product_json product_info app_name data_folder
    exe="$(find_electron_ancestor "$start_pid")"
    if [[ -z "$exe" ]]; then
        log_error "could not locate the editor process in the process tree"
        return 1
    fi

    app_root="$(dirname "$exe")"
    product_json="$app_root/resources/app/product.json"

    product_info="$(read_product_json "$product_json")" || {
        log_error "failed to read product.json at $product_json"
        return 1
    }
    app_name="$(sed -n '1p' <<<"$product_info")"
    data_folder="$(sed -n '2p' <<<"$product_info")"

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

    if [[ -n "$data_folder" ]]; then
        local candidate found_existing=""
        while IFS= read -r candidate; do
            if [[ -d "$candidate" ]]; then
                EDITOR_CONFIG_DIR="$candidate"
                found_existing="1"
                break
            fi
        done < <(_config_dir_candidates "$data_folder")

        if [[ -z "$found_existing" ]]; then
            EDITOR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$data_folder/User"
        else
            log_info "using config directory: $EDITOR_CONFIG_DIR"
        fi
    else
        log_warn "product.json has no dataFolderName - settings/keybindings will be skipped"
    fi

    return 0
}
