#!/usr/bin/env bash
# install-editor-setup.sh - apply personal extensions/font/settings/
# keybindings/mcp to whichever VS Code-family editor's integrated
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

    log_info "iniciando instalação de customizações do editor"

    resolve_editor_paths || true

    if [[ -n "$EDITOR_APP_NAME" ]]; then
        log_info "editor detectado: $EDITOR_APP_NAME"
        record_step "detecção do editor ($EDITOR_APP_NAME)" "OK"
    else
        record_step "detecção do editor" "ERRO"
    fi

    install_extensions "$EDITOR_BIN"
    install_font
    apply_settings "$EDITOR_CONFIG_DIR"
    apply_mcp "$EDITOR_MCP_PATH"

    print_summary
    log_info "log completo em $LOG_FILE"
}

# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck source=lib/apply.sh
source "$SCRIPT_DIR/lib/apply.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
