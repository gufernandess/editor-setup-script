tmpdir="$(mktemp -d)"

# Case 1: target missing -> overlay written as-is
cat > "$tmpdir/overlay_obj.json" <<'EOF'
{"settings": {"a": 1, "b": 2}}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target1.json" "$tmpdir/overlay_obj.json" --overlay-key settings
result1="$(cat "$tmpdir/target1.json")"
assert_contains "$result1" '"a": 1' "merge with no existing target should write the overlay as-is"

# Case 2: shallow object merge - overlay wins, target-only keys preserved
cat > "$tmpdir/target2.json" <<'EOF'
{"a": 1, "c": 3}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target2.json" "$tmpdir/overlay_obj.json" --overlay-key settings
result2="$(python3 -c "import json; d=json.load(open('$tmpdir/target2.json')); print(d['a'], d['b'], d['c'])")"
assert_eq "1 2 3" "$result2" "object merge should overwrite a, add b, keep c"

# Case 3: array union merge, deduped
cat > "$tmpdir/target3.json" <<'EOF'
[{"key": "ctrl+x"}]
EOF
cat > "$tmpdir/overlay_arr.json" <<'EOF'
{"keybindings": [{"key": "ctrl+x"}, {"key": "ctrl+y"}]}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target3.json" "$tmpdir/overlay_arr.json" --overlay-key keybindings
result3_len="$(python3 -c "import json; print(len(json.load(open('$tmpdir/target3.json'))))")"
assert_eq "2" "$result3_len" "array merge should dedupe and end up with 2 items"

# Case 4: malformed JSON in target file should error cleanly
cat > "$tmpdir/target4.json" <<'EOF'
{invalid json
EOF
cat > "$tmpdir/overlay4.json" <<'EOF'
{"key": "value"}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target4.json" "$tmpdir/overlay4.json" 2>"$tmpdir/err4.txt"
exit_code=$?
err_output="$(cat "$tmpdir/err4.txt")"
assert_eq "1" "$exit_code" "malformed target JSON should exit with code 1"
assert_contains "$err_output" "error:" "error message should contain 'error:'"
assert_contains "$err_output" "not valid JSON" "error message should mention 'not valid JSON'"
# Verify no Python traceback in the error output
if echo "$err_output" | grep -q "Traceback"; then
    echo "  FAIL: malformed target should not print Python traceback"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    TESTS_RUN=$((TESTS_RUN + 1))
fi

# Case 5: --nested-merge-key merges within a nested key instead of replacing
# it wholesale (this is how mcp.json's mcpServers / powers.mcpServers must
# behave so a user's existing MCP servers survive the merge)
cat > "$tmpdir/target5.json" <<'EOF'
{"mcpServers": {"existing": {"command": "foo"}}, "powers": {"mcpServers": {"existing-power": {"url": "x"}}}}
EOF
cat > "$tmpdir/overlay5.json" <<'EOF'
{"mcp": {"mcpServers": {"new": {"command": "bar"}}, "powers": {"mcpServers": {"new-power": {"url": "y"}}}}}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target5.json" "$tmpdir/overlay5.json" --overlay-key mcp --nested-merge-key mcpServers --nested-merge-key powers.mcpServers
result5="$(cat "$tmpdir/target5.json")"
assert_contains "$result5" '"existing"' "nested-merge-key should preserve a pre-existing mcpServers entry"
assert_contains "$result5" '"new"' "nested-merge-key should add the overlay's mcpServers entry"
assert_contains "$result5" '"existing-power"' "nested-merge-key should preserve a pre-existing powers.mcpServers entry"
assert_contains "$result5" '"new-power"' "nested-merge-key should add the overlay's powers.mcpServers entry"

# Case 6: JSONC target (// comment header, like VS Code's real
# keybindings.json, plus a trailing comma) should still parse and merge
cat > "$tmpdir/target6.json" <<'EOF'
// Place your key bindings in this file to override the defaults
[
  {"key": "ctrl+q", "command": "existing.command"},
]
EOF
cat > "$tmpdir/overlay6.json" <<'EOF'
{"keybindings": [{"key": "ctrl+k", "command": "noop"}]}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target6.json" "$tmpdir/overlay6.json" --overlay-key keybindings
exit_code6=$?
result6="$(cat "$tmpdir/target6.json")"
assert_eq "0" "$exit_code6" "JSONC target with a comment header should merge successfully"
assert_contains "$result6" '"existing.command"' "JSONC merge should keep the pre-existing keybinding"
assert_contains "$result6" '"noop"' "JSONC merge should add the overlay's keybinding"

rm -rf "$tmpdir"
