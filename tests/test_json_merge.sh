tmpdir="$(mktemp -d)"

# Case 1: target missing -> overlay written as-is
cat > "$tmpdir/overlay_obj.json" <<'EOF'
{"settings": {"a": 1, "b": 2}}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target1.json" "$tmpdir/overlay_obj.json" --overlay-key settings
result1="$(cat "$tmpdir/target1.json")"
assert_contains "$result1" '"a": 1' "missing target should get the overlay written as-is"

# Case 2: target exists with different content -> fully replaced, not merged
cat > "$tmpdir/target2.json" <<'EOF'
{"a": 1, "c": 3}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target2.json" "$tmpdir/overlay_obj.json" --overlay-key settings
result2_normalized="$(python3 -c "import json; print(json.dumps(json.load(open('$tmpdir/target2.json')), sort_keys=True))")"
assert_eq '{"a": 1, "b": 2}' "$result2_normalized" "existing target should be fully replaced by the overlay - target-only key 'c' must not survive"

# Case 3: array target -> also fully replaced, old items dropped
cat > "$tmpdir/target3.json" <<'EOF'
[{"key": "ctrl+x"}]
EOF
cat > "$tmpdir/overlay_arr.json" <<'EOF'
{"keybindings": [{"key": "ctrl+y"}]}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target3.json" "$tmpdir/overlay_arr.json" --overlay-key keybindings
result3_normalized="$(python3 -c "import json; print(json.dumps(json.load(open('$tmpdir/target3.json'))))")"
assert_eq '[{"key": "ctrl+y"}]' "$result3_normalized" "array target should be fully replaced by the overlay array"

# Case 4: overlay-key not found in the overlay source -> clean error
cat > "$tmpdir/overlay_missing.json" <<'EOF'
{"other": 1}
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target4.json" "$tmpdir/overlay_missing.json" --overlay-key nope 2>"$tmpdir/err4.txt"
exit_code4=$?
err_output4="$(cat "$tmpdir/err4.txt")"
assert_eq "1" "$exit_code4" "missing overlay-key should exit with code 1"
assert_contains "$err_output4" "not found" "error message should mention the key was not found"

# Case 5: malformed/JSONC existing target doesn't matter anymore - it's
# never read, only ever replaced, so it can't break the write
cat > "$tmpdir/target5.json" <<'EOF'
// this is not valid JSON at all, doesn't matter {{{
EOF
python3 "$PROJECT_ROOT/lib/json_merge.py" "$tmpdir/target5.json" "$tmpdir/overlay_obj.json" --overlay-key settings
exit_code5=$?
result5="$(cat "$tmpdir/target5.json")"
assert_eq "0" "$exit_code5" "a malformed/JSONC existing target should not matter - it's replaced, never parsed"
assert_contains "$result5" '"a": 1' "malformed existing target should end up fully replaced by the overlay"

rm -rf "$tmpdir"
