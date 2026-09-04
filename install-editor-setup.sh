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
    export CUSTOMIZATIONS_JSON LOG_FILE SCRIPT_DIR

    log_info "starting editor customization install"

    resolve_editor_paths || true
    export EDITOR_APP_NAME EDITOR_BIN EDITOR_CONFIG_DIR EDITOR_PID

    log_info "closing the editor so changes apply without it racing to overwrite them - it will relaunch automatically in a few seconds"

    # The whole pipeline below (stop editor, install, relaunch) runs detached
    # (new session) so it survives both the editor process and this script's
    # own terminal dying once the editor is killed.
    setsid bash -c '
        source "$SCRIPT_DIR/lib/log.sh"
        source "$SCRIPT_DIR/lib/detect.sh"
        source "$SCRIPT_DIR/lib/apply.sh"
        run_install_pipeline
    ' >/dev/null 2>&1 </dev/null &
    disown
}

source "$SCRIPT_DIR/lib/log.sh"

source "$SCRIPT_DIR/lib/detect.sh"

source "$SCRIPT_DIR/lib/apply.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
