#!/usr/bin/env bash
# lib/log.sh - timestamped logging + step-outcome summary.
# Requires LOG_FILE to be set by the caller before sourcing.

LOG_FILE="${LOG_FILE:-$HOME/.editor-setup-install.log}"
STEP_NAMES=()
STEP_STATUSES=()

_log_line() {
    local level="$1" msg="$2" line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg"
    echo "$line"
    echo "$line" >> "$LOG_FILE"
}

log_info()  { _log_line "INFO" "$1"; }
log_ok()    { _log_line "OK" "$1"; }
log_warn()  { _log_line "WARN" "$1"; }
log_error() { _log_line "ERROR" "$1"; }

record_step() {
    STEP_NAMES+=("$1")
    STEP_STATUSES+=("$2")
}

print_summary() {
    echo
    echo "===== Summary ====="
    local i
    for i in "${!STEP_NAMES[@]}"; do
        printf "  [%s] %s\n" "${STEP_STATUSES[$i]}" "${STEP_NAMES[$i]}"
    done
    echo "==================="
}
