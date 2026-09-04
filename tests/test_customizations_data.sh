#!/usr/bin/env bash
validation_output="$(python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/customizations.json'))
assert isinstance(d['extensions'], list) and len(d['extensions']) == 17, 'extensions should have 17 items'
assert {'name', 'version', 'download_url'}.issubset(d['font'].keys()), 'font should have name/version/download_url'
assert 'workbench.colorTheme' in d['settings'], 'settings should include workbench.colorTheme'
assert isinstance(d['keybindings'], list), 'keybindings should be an array'
assert 'mcpServers' in d['mcp'], 'mcp should include mcpServers'
print('OK')
" 2>&1)"
assert_eq "OK" "$validation_output" "customizations.json should be valid and match the expected shape"
