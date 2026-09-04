#!/usr/bin/env bash
# lib/apply.sh - install extensions/font, apply settings/keybindings/mcp.
# Requires lib/log.sh already sourced. Reads CUSTOMIZATIONS_JSON.

FONT_INSTALL_DIR="${FONT_INSTALL_DIR:-$HOME/.local/share/fonts/JetBrainsMono}"
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_download_file() {
    curl -fsSL -o "$2" "$1"
}

_extract_zip() {
    unzip -oq "$1" -d "$2"
}

install_extensions() {
    local editor_bin="$1"
    if [[ -z "$editor_bin" ]]; then
        log_warn "skipping extension install: no editor binary resolved"
        record_step "extensions" "SKIPPED"
        return 0
    fi

    local ids
    ids="$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print('\n'.join(d['extensions']))
" "$CUSTOMIZATIONS_JSON")"

    local ok=0 fail=0 id
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        if "$editor_bin" --install-extension "$id" >>"$LOG_FILE" 2>&1; then
            log_ok "extension installed: $id"
            ok=$((ok + 1))
        else
            log_error "failed to install extension: $id"
            fail=$((fail + 1))
        fi
    done <<<"$ids"

    if [[ "$fail" -eq 0 ]]; then
        record_step "extensions: $ok ok, $fail failed" "OK"
    else
        record_step "extensions: $ok ok, $fail failed" "WARN"
    fi
    return 0
}

install_font() {
    if compgen -G "$FONT_INSTALL_DIR/*.ttf" >/dev/null 2>&1; then
        log_ok "font already present at $FONT_INSTALL_DIR, skipping download"
        record_step "font" "OK"
        return 0
    fi

    local name url tmpdir zip_path
    name="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['font']['name'])" "$CUSTOMIZATIONS_JSON")"
    url="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['font']['download_url'])" "$CUSTOMIZATIONS_JSON")"

    tmpdir="$(mktemp -d)"
    zip_path="$tmpdir/font.zip"

    if ! _download_file "$url" "$zip_path" >>"$LOG_FILE" 2>&1; then
        log_warn "failed to download font $name from $url - skipping"
        record_step "font" "WARN"
        rm -rf "$tmpdir"
        return 1
    fi

    mkdir -p "$FONT_INSTALL_DIR"
    if ! _extract_zip "$zip_path" "$tmpdir/extracted" >>"$LOG_FILE" 2>&1; then
        log_warn "failed to extract font $name - skipping"
        record_step "font" "WARN"
        rm -rf "$tmpdir"
        return 1
    fi

    find "$tmpdir/extracted" -iname "*.ttf" -exec cp {} "$FONT_INSTALL_DIR/" \;

    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$FONT_INSTALL_DIR" >>"$LOG_FILE" 2>&1
    fi

    rm -rf "$tmpdir"
    log_ok "font $name installed at $FONT_INSTALL_DIR"
    record_step "font" "OK"
    return 0
}

_apply_json_key() {
    local config_dir="$1" filename="$2" overlay_key="$3" step_label="$4"
    local target="$config_dir/$filename"

    mkdir -p "$config_dir"

    if [[ -f "$target" ]]; then
        cp "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
    fi

    if python3 "$SCRIPT_LIB_DIR/json_merge.py" "$target" "$CUSTOMIZATIONS_JSON" --overlay-key "$overlay_key" >>"$LOG_FILE" 2>&1; then
        log_ok "$step_label applied to $target"
        record_step "$step_label" "OK"
        return 0
    else
        log_error "failed to apply $step_label to $target"
        record_step "$step_label" "ERROR"
        return 1
    fi
}

apply_settings() {
    local config_dir="$1"
    if [[ -z "$config_dir" ]]; then
        log_warn "skipping settings/keybindings: config_dir not resolved"
        record_step "settings" "SKIPPED"
        record_step "keybindings" "SKIPPED"
        return 0
    fi
    _apply_json_key "$config_dir" "settings.json" "settings" "settings"
    _apply_json_key "$config_dir" "keybindings.json" "keybindings" "keybindings"
}

apply_mcp() {
    local mcp_path="$1"
    if [[ -z "$mcp_path" ]]; then
        log_warn "skipping mcp.json: mcp_path not resolved"
        record_step "mcp" "SKIPPED"
        return 0
    fi
    local mcp_dir
    mcp_dir="$(dirname "$mcp_path")"
    _apply_json_key "$mcp_dir" "$(basename "$mcp_path")" "mcp" "mcp"
    log_info "MCP servers that require login (e.g. figma) need manual authentication afterward"
}
