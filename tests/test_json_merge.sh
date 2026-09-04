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

rm -rf "$tmpdir"
