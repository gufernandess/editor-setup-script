tmpdir="$(mktemp -d)"
LOG_FILE="$tmpdir/log.txt"
export LOG_FILE
STEP_NAMES=()
STEP_STATUSES=()
source "$PROJECT_ROOT/lib/log.sh"

out="$(log_ok "extension installed")"
assert_contains "$out" "[OK]" "log_ok should include the OK prefix"
assert_contains "$out" "extension installed" "log_ok should include the message"

file_content="$(cat "$LOG_FILE")"
assert_contains "$file_content" "extension installed" "log_ok should also append to LOG_FILE"

record_step "install extensions" "OK"
record_step "font" "WARN"
summary_out="$(print_summary)"
assert_contains "$summary_out" "install extensions" "summary should list the step name"
assert_contains "$summary_out" "[WARN]" "summary should show the WARN status"

rm -rf "$tmpdir"
