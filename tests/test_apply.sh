tmpdir="$(mktemp -d)"
LOG_FILE="$tmpdir/log.txt"
export LOG_FILE
STEP_NAMES=()
STEP_STATUSES=()
source "$PROJECT_ROOT/lib/log.sh"
source "$PROJECT_ROOT/lib/apply.sh"

cat > "$tmpdir/customizations.json" <<'EOF'
{
  "extensions": ["pub.good-ext", "pub.bad-ext"],
  "font": {"name": "TestFont", "version": "1.0", "download_url": "https://example.invalid/font.zip"},
  "settings": {"editor.fontSize": 16, "editor.tabSize": 2},
  "keybindings": [{"key": "ctrl+k", "command": "noop"}],
  "mcp": {"mcpServers": {"fetch": {"command": "uvx"}}}
}
EOF
CUSTOMIZATIONS_JSON="$tmpdir/customizations.json"
export CUSTOMIZATIONS_JSON

# --- install_extensions: one id fails, one succeeds ---
fake_bin="$tmpdir/fake_editor_bin.sh"
cat > "$fake_bin" <<'EOF'
#!/usr/bin/env bash
if [[ "$2" == "pub.bad-ext" ]]; then
    exit 1
fi
exit 0
EOF
chmod +x "$fake_bin"

STEP_NAMES=(); STEP_STATUSES=()
install_extensions "$fake_bin"
summary="$(print_summary)"
assert_contains "$summary" "1 ok, 1 falharam" "summary should count one success and one failure"

# --- install_extensions: no editor_bin resolved ---
STEP_NAMES=(); STEP_STATUSES=()
install_extensions ""
summary2="$(print_summary)"
assert_contains "$summary2" "SKIPPED" "should skip extensions when no editor_bin was resolved"

# --- install_font: font already present ---
FONT_INSTALL_DIR="$tmpdir/fonts_present"
mkdir -p "$FONT_INSTALL_DIR"
touch "$FONT_INSTALL_DIR/Existing.ttf"
export FONT_INSTALL_DIR
STEP_NAMES=(); STEP_STATUSES=()
install_font
summary3="$(print_summary)"
assert_contains "$summary3" "[OK] fonte" "should skip the download when the font already exists"

# --- install_font: download fails ---
FONT_INSTALL_DIR="$tmpdir/fonts_missing"
export FONT_INSTALL_DIR
_download_file() { return 1; }
STEP_NAMES=(); STEP_STATUSES=()
install_font
summary4="$(print_summary)"
assert_contains "$summary4" "[AVISO] fonte" "should log a warning (not fail) when the download fails"

# --- apply_settings: no config_dir resolved ---
STEP_NAMES=(); STEP_STATUSES=()
apply_settings ""
summary5="$(print_summary)"
assert_contains "$summary5" "SKIPPED" "should skip settings when no config_dir was resolved"

# --- apply_settings: merges into an existing settings.json, with backup ---
config_dir="$tmpdir/config/User"
mkdir -p "$config_dir"
cat > "$config_dir/settings.json" <<'EOF'
{"editor.tabSize": 4, "editor.wordWrap": "on"}
EOF
STEP_NAMES=(); STEP_STATUSES=()
apply_settings "$config_dir"
merged="$(cat "$config_dir/settings.json")"
assert_contains "$merged" '"editor.fontSize": 16' "settings.json should gain the new key"
assert_contains "$merged" '"editor.wordWrap": "on"' "settings.json should keep a key only the destination had"
assert_contains "$merged" '"editor.tabSize": 2' "settings.json should let the overlay win on a conflicting key"
backup_count="$(find "$config_dir" -name "settings.json.bak.*" | wc -l)"
assert_eq "1" "$backup_count" "should have backed up the existing settings.json"

# --- apply_mcp: preserves a pre-existing MCP server not in the overlay ---
mcp_path="$tmpdir/mcp_config/mcp.json"
mkdir -p "$(dirname "$mcp_path")"
cat > "$mcp_path" <<'EOF'
{"mcpServers": {"my-existing-server": {"command": "foo"}}}
EOF
STEP_NAMES=(); STEP_STATUSES=()
apply_mcp "$mcp_path"
mcp_result="$(cat "$mcp_path")"
assert_contains "$mcp_result" '"my-existing-server"' "apply_mcp should keep a pre-existing MCP server not present in the overlay"
assert_contains "$mcp_result" '"fetch"' "apply_mcp should still add the overlay's MCP server"

rm -rf "$tmpdir"
