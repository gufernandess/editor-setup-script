tmpdir="$(mktemp -d)"
LOG_FILE="$tmpdir/log.txt"
export LOG_FILE
STEP_NAMES=()
STEP_STATUSES=()
source "$PROJECT_ROOT/lib/log.sh"
source "$PROJECT_ROOT/lib/detect.sh"

# --- Sanity check against the REAL /proc, before any mocking ---
real_ppid_from_proc="$(_proc_parent_pid "$$")"
real_ppid_from_ps="$(ps -o ppid= -p "$$" | tr -d ' ')"
assert_eq "$real_ppid_from_ps" "$real_ppid_from_proc" "_proc_parent_pid should match ps -o ppid= for the real test process"

real_exe="$(_proc_exe_path "$$")"
assert_file_exists "$real_exe" "_proc_exe_path should resolve a real executable path for the current process"

# --- Fixture: a fake editor install with a product.json ---
mkdir -p "$tmpdir/fake_editor/resources/app" "$tmpdir/fake_editor/bin"
cat > "$tmpdir/fake_editor/resources/app/product.json" <<'EOF'
{"applicationName": "testeditor", "dataFolderName": "TestEditor"}
EOF
touch "$tmpdir/fake_editor/testeditor" "$tmpdir/fake_editor/bin/testeditor"
chmod +x "$tmpdir/fake_editor/testeditor" "$tmpdir/fake_editor/bin/testeditor"

# --- find_electron_ancestor: walk through two non-matching ancestors ---
declare -A FAKE_EXE=( [100]="/bin/bash" [200]="/bin/bash" [300]="$tmpdir/fake_editor/testeditor" )
declare -A FAKE_PARENT=( [100]=200 [200]=300 [300]=1 )
_proc_exe_path() { echo "${FAKE_EXE[$1]:-}"; }
_proc_parent_pid() { echo "${FAKE_PARENT[$1]:-}"; }

found_exe="$(find_electron_ancestor 100)"
assert_eq "$tmpdir/fake_editor/testeditor" "$found_exe" "find_electron_ancestor should walk up and find the editor process"

# --- read_product_json ---
product_info="$(read_product_json "$tmpdir/fake_editor/resources/app/product.json")"
assert_eq "testeditor" "$(sed -n '1p' <<<"$product_info")" "read_product_json line 1 should be applicationName"
assert_eq "TestEditor" "$(sed -n '2p' <<<"$product_info")" "read_product_json line 2 should be dataFolderName"

# --- resolve_editor_paths: happy path ---
TERM_PROGRAM="testeditor"
resolve_editor_paths 100
assert_eq "testeditor" "$EDITOR_APP_NAME" "EDITOR_APP_NAME should come from product.json"
assert_eq "$tmpdir/fake_editor/bin/testeditor" "$EDITOR_BIN" "EDITOR_BIN should use the app_root/bin/<name> layout"
assert_eq "$HOME/.config/TestEditor/User" "$EDITOR_CONFIG_DIR" "EDITOR_CONFIG_DIR should come from dataFolderName"
assert_eq "$HOME/.testeditor/settings/mcp.json" "$EDITOR_MCP_PATH" "EDITOR_MCP_PATH should follow the ~/.<app>/settings/mcp.json convention"

# --- resolve_editor_paths: no editor found in the process tree ---
declare -A FAKE_EXE2=( [500]="/bin/bash" [600]="/bin/bash" )
declare -A FAKE_PARENT2=( [500]=600 [600]=1 )
_proc_exe_path() { echo "${FAKE_EXE2[$1]:-}"; }
_proc_parent_pid() { echo "${FAKE_PARENT2[$1]:-}"; }
resolve_editor_paths 500
result=$?
assert_eq "1" "$result" "resolve_editor_paths should return 1 when no editor is found"
assert_eq "" "$EDITOR_BIN" "EDITOR_BIN should stay empty when no editor is found"

# --- resolve_editor_paths: TERM_PROGRAM unset ---
unset TERM_PROGRAM
resolve_editor_paths 100
result2=$?
assert_eq "1" "$result2" "resolve_editor_paths should return 1 when TERM_PROGRAM is unset"

# --- read_product_json: malformed product.json should error cleanly,
# with no raw Python traceback on stderr ---
cat > "$tmpdir/bad_product.json" <<'EOF'
{not valid json
EOF
bad_output="$(read_product_json "$tmpdir/bad_product.json" 2>&1 >/dev/null)"
bad_exit=$?
assert_eq "1" "$bad_exit" "read_product_json should exit 1 on malformed product.json"
if echo "$bad_output" | grep -q "Traceback"; then
    echo "  FAIL: read_product_json should not print a Python traceback on malformed product.json"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_RUN=$((TESTS_RUN + 1))
fi

rm -rf "$tmpdir"
