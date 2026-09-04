tmpdir="$(mktemp -d)"

cat > "$tmpdir/customizations.json" <<'EOF'
{
  "extensions": [],
  "font": {"name": "TestFont", "version": "1.0", "download_url": "https://example.invalid/font.zip"},
  "settings": {},
  "keybindings": [],
  "mcp": {}
}
EOF

CUSTOMIZATIONS_JSON="$tmpdir/customizations.json"
LOG_FILE="$tmpdir/log.txt"
FONT_INSTALL_DIR="$tmpdir/fonts"
export CUSTOMIZATIONS_JSON LOG_FILE FONT_INSTALL_DIR

source "$PROJECT_ROOT/install-editor-setup.sh"

unset TERM_PROGRAM
_download_file() { return 1; }

output="$(main)"

assert_contains "$output" "detecção do editor" "summary should include the detection step"
assert_contains "$output" "[ERRO]" "detection should show as ERRO when TERM_PROGRAM is unset"
assert_contains "$output" "SKIPPED" "extensions/settings/mcp should show as skipped when detection fails"
assert_contains "$output" "fonte" "font step should still run even though detection failed"

rm -rf "$tmpdir"
