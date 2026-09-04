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
    EDITOR_MCP_PATH=""

    if [[ -z "${TERM_PROGRAM:-}" ]]; then
        log_error "TERM_PROGRAM não definido - rode este script de dentro do terminal integrado do editor"
        return 1
    fi

    local exe app_root product_json product_info app_name data_folder
    exe="$(find_electron_ancestor "$start_pid")"
    if [[ -z "$exe" ]]; then
        log_error "não foi possível localizar o processo do editor na árvore de processos"
        return 1
    fi

    app_root="$(dirname "$exe")"
    product_json="$app_root/resources/app/product.json"

    product_info="$(read_product_json "$product_json")" || {
        log_error "falha ao ler product.json em $product_json"
        return 1
    }
    app_name="$(sed -n '1p' <<<"$product_info")"
    data_folder="$(sed -n '2p' <<<"$product_info")"

    if [[ -z "$app_name" ]]; then
        log_error "product.json em $product_json não contém applicationName"
        return 1
    fi

    if [[ "$app_name" != "$TERM_PROGRAM" ]]; then
        log_warn "applicationName ($app_name) difere de TERM_PROGRAM ($TERM_PROGRAM) - seguindo com $app_name"
    fi

    EDITOR_APP_NAME="$app_name"

    if [[ -x "$app_root/bin/$app_name" ]]; then
        EDITOR_BIN="$app_root/bin/$app_name"
    elif command -v "$app_name" >/dev/null 2>&1; then
        EDITOR_BIN="$(command -v "$app_name")"
        log_warn "usando $EDITOR_BIN do PATH (layout $app_root/bin/$app_name não encontrado)"
    else
        log_error "não encontrei o binário de CLI do editor (tentei $app_root/bin/$app_name e o PATH)"
    fi

    if [[ -n "$data_folder" ]]; then
        EDITOR_CONFIG_DIR="$HOME/.config/$data_folder/User"
    else
        log_warn "product.json não contém dataFolderName - settings/keybindings serão pulados"
    fi

    EDITOR_MCP_PATH="$HOME/.$app_name/settings/mcp.json"

    return 0
}
