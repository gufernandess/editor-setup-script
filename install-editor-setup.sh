#!/usr/bin/env bash
# install-editor-setup.sh - apply personal extensions/font/settings/
# keybindings to whichever VS Code-family editor's integrated
# terminal this is run from.
#
# Usage: from inside the target editor's own integrated terminal:
#   bash install-editor-setup.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
    CUSTOMIZATIONS_JSON="${CUSTOMIZATIONS_JSON:-$SCRIPT_DIR/customizations.json}"
    LOG_FILE="${LOG_FILE:-$HOME/.editor-setup-install.log}"
    export CUSTOMIZATIONS_JSON LOG_FILE

    log_info "starting editor customization install"

    resolve_editor_paths || true

    if [[ -n "$EDITOR_APP_NAME" ]]; then
        log_info "editor detected: $EDITOR_APP_NAME"
        record_step "editor detection ($EDITOR_APP_NAME)" "OK"
    else
        record_step "editor detection" "ERROR"
    fi

    install_extensions "$EDITOR_BIN"
    install_font
    apply_settings "$EDITOR_CONFIG_DIR"

    print_summary
    log_info "full log at $LOG_FILE"
}

source "$SCRIPT_DIR/lib/log.sh"

source "$SCRIPT_DIR/lib/detect.sh"

source "$SCRIPT_DIR/lib/apply.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
