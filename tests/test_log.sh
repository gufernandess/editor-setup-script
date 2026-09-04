tmpdir="$(mktemp -d)"
LOG_FILE="$tmpdir/log.txt"
export LOG_FILE
STEP_NAMES=()
STEP_STATUSES=()
source "$PROJECT_ROOT/lib/log.sh"

out="$(log_ok "extensao instalada")"
assert_contains "$out" "[OK]" "log_ok should include the OK prefix"
assert_contains "$out" "extensao instalada" "log_ok should include the message"

file_content="$(cat "$LOG_FILE")"
assert_contains "$file_content" "extensao instalada" "log_ok should also append to LOG_FILE"

record_step "instalar extensoes" "OK"
record_step "fonte" "AVISO"
summary_out="$(print_summary)"
assert_contains "$summary_out" "instalar extensoes" "summary should list the step name"
assert_contains "$summary_out" "[AVISO]" "summary should show the AVISO status"

rm -rf "$tmpdir"
