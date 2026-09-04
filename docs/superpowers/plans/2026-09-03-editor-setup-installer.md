# Editor Setup Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shell script that, run from inside any VS Code-family editor's own integrated terminal, detects that editor and applies a fixed set of extensions, a font, editor settings, keybindings, and MCP server config to it — regardless of which editor it is or how it was installed.

**Architecture:** A bash entry point sources three libraries (`log.sh` for timestamped logging + a step-outcome summary, `detect.sh` for locating the running editor via process-tree walking and its `product.json`, `apply.sh` for the four idempotent apply steps) and a Python helper (`json_merge.py`, since no `jq` is installed) for shallow-merging JSON. All customization data lives in one file, `customizations.json`, captured as a static snapshot of the current local Kiro install. No step's failure stops another step from running.

**Tech Stack:** bash, python3 (JSON handling only — no `jq`/`bats` available on this machine), curl, unzip, fontconfig (`fc-cache`).

**Spec:** `docs/superpowers/specs/2026-09-03-editor-setup-installer-design.md`

## Global Constraints

- Project root: `~/projects/editor-setup/` (own git repo, already initialized).
- No `set -e` anywhere — every step is isolated; a failure is logged and execution continues (per spec's Logging and resilience section).
- `customizations.json` is the single data file; no per-editor profile split — every customization is applied regardless of which editor was detected (per spec's non-goals).
- Every write to an existing settings/keybindings/mcp file is preceded by a timestamped backup (`<file>.bak.<timestamp>`); never overwrite without one.
- Font pinned to JetBrains Mono 2.304, matching the version already installed locally.
- No `jq` or `bats` on this machine — JSON handling goes through `python3`, tests use a hand-rolled bash harness (no new dependency to install).
- Real validation against snap/pacman/pamac installs is explicitly deferred by the user to later manual testing; this plan tests everything that's testable without a running editor (process-tree parsing against the real test process, JSON merge logic, degraded-path flow control) and stops there.

---

## Task 1: Test harness scaffolding

**Files:**
- Create: `tests/test_helper.sh`
- Create: `tests/run_tests.sh`
- Create: `tests/test_example.sh`

**Interfaces:**
- Produces: `assert_eq(expected, actual, msg)`, `assert_contains(haystack, needle, msg)`, `assert_file_exists(path, msg)` — bash functions, each incrementing the caller's `TESTS_RUN`/`TESTS_FAILED` counters and printing a `FAIL:` line on failure. `tests/run_tests.sh` sources `test_helper.sh`, then sources every `tests/test_*.sh` (except itself and the helper) in a single shell, and exits 1 if any assertion failed. `PROJECT_ROOT` is set as a plain shell variable pointing at the repo root, visible to every sourced test file.

- [ ] **Step 1: Write `tests/test_helper.sh`**

```bash
#!/usr/bin/env bash
# Minimal assertion helpers for the hand-rolled test harness.
# Relies on TESTS_RUN / TESTS_FAILED being declared by the caller.

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_eq}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        return 0
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg - expected [$expected] got [$actual]"
    return 1
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-assert_contains}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg - [$haystack] does not contain [$needle]"
    return 1
}

assert_file_exists() {
    local path="$1" msg="${2:-assert_file_exists}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$path" ]]; then
        return 0
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg - [$path] does not exist"
    return 1
}
```

- [ ] **Step 2: Write `tests/run_tests.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

TESTS_RUN=0
TESTS_FAILED=0

source "$TEST_DIR/test_helper.sh"

for test_file in "$TEST_DIR"/test_*.sh; do
    base="$(basename "$test_file")"
    [[ "$base" == "test_helper.sh" ]] && continue
    echo "== $base =="
    source "$test_file"
done

echo
echo "Total: $TESTS_RUN run, $TESTS_FAILED failed"
[[ "$TESTS_FAILED" -eq 0 ]]
```

- [ ] **Step 3: Write a smoke test to prove the harness works**

```bash
# tests/test_example.sh
assert_eq "1" "1" "sanity: equal strings should pass"
assert_contains "hello world" "world" "sanity: substring should pass"
```

- [ ] **Step 4: Run it and verify the summary**

Run: `bash tests/run_tests.sh`
Expected: prints `== test_example.sh ==` then `Total: 2 run, 0 failed`, exits 0.

- [ ] **Step 5: Commit**

```bash
cd /home/gusta/projects/editor-setup
git add tests/test_helper.sh tests/run_tests.sh tests/test_example.sh
git commit -m "$(cat <<'EOF'
Add bash test harness

No bats/jq available on this machine, so the plan uses a hand-rolled
assert_eq/assert_contains/assert_file_exists harness that sources
every tests/test_*.sh into one shell and reports a pass/fail count.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nb3bwco447DWeTGiyrmyZg
EOF
)"
```

---

## Task 2: Logging and step-outcome summary

**Files:**
- Create: `lib/log.sh`
- Create: `tests/test_log.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `log_info(msg)`, `log_ok(msg)`, `log_warn(msg)`, `log_error(msg)` — each prints one timestamped, level-prefixed line to stdout and appends it to `$LOG_FILE`. `record_step(name, status)` appends to the module-level `STEP_NAMES`/`STEP_STATUSES` arrays. `print_summary()` prints every recorded step as `  [STATUS] name`. Every later task that logs anything or records a step depends on this file being sourced first.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_log.sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run_tests.sh`
Expected: FAIL — `lib/log.sh: No such file or directory` (source error), since the file doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```bash
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
log_warn()  { _log_line "AVISO" "$1"; }
log_error() { _log_line "ERRO" "$1"; }

record_step() {
    STEP_NAMES+=("$1")
    STEP_STATUSES+=("$2")
}

print_summary() {
    echo
    echo "===== Resumo ====="
    local i
    for i in "${!STEP_NAMES[@]}"; do
        printf "  [%s] %s\n" "${STEP_STATUSES[$i]}" "${STEP_NAMES[$i]}"
    done
    echo "==================="
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run_tests.sh`
Expected: `== test_log.sh ==` with no `FAIL:` lines, `Total: 6 run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add lib/log.sh tests/test_log.sh
git commit -m "$(cat <<'EOF'
Add lib/log.sh: timestamped logging and step-outcome summary

Every step in the installer logs through this and records its own
outcome (OK/AVISO/ERRO/SKIPPED), so a failure anywhere is visible in
the final summary without needing to read the full log file.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nb3bwco447DWeTGiyrmyZg
EOF
)"
```

---

## Task 3: JSON shallow-merge helper

**Files:**
- Create: `lib/json_merge.py`
- Create: `tests/test_json_merge.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: CLI `python3 lib/json_merge.py <target_path> <overlay_source_path> [--overlay-key KEY]`. If `target_path` is missing or empty, writes the overlay value as-is. If both target and overlay (after optional `--overlay-key` extraction) are JSON objects, shallow-merges with overlay winning per key. If both are JSON arrays, appends overlay items not already present (by deep equality), preserving target order first. Exits 1 with a message on stderr for any other type mismatch. This is the merge engine `apply.sh` (Task 6) uses for settings/keybindings/mcp.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_json_merge.sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run_tests.sh`
Expected: FAIL — `python3: can't open file '.../lib/json_merge.py'`.

- [ ] **Step 3: Write minimal implementation**

```python
#!/usr/bin/env python3
"""Shallow-merge a JSON overlay value into a target JSON file.

Usage:
    json_merge.py <target_path> <overlay_source_path> [--overlay-key KEY]

If --overlay-key is given, the overlay value is
json.load(overlay_source_path)[KEY]; otherwise it's the whole content
of overlay_source_path. If target_path is missing or empty, the
overlay is written as-is. Objects merge shallowly (overlay wins per
key, target-only keys survive). Arrays merge as a deduped union
(target items first, then overlay items not already present). Any
other type combination is an error.
"""
import argparse
import json
import sys


def shallow_merge(target, overlay):
    if isinstance(target, dict) and isinstance(overlay, dict):
        merged = dict(target)
        merged.update(overlay)
        return merged
    if isinstance(target, list) and isinstance(overlay, list):
        merged = list(target)
        for item in overlay:
            if item not in merged:
                merged.append(item)
        return merged
    raise TypeError(
        f"cannot merge {type(target).__name__} target with "
        f"{type(overlay).__name__} overlay"
    )


def load_json_or_none(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read().strip()
    except FileNotFoundError:
        return None
    return json.loads(content) if content else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target_path")
    parser.add_argument("overlay_source_path")
    parser.add_argument("--overlay-key", default=None)
    args = parser.parse_args()

    with open(args.overlay_source_path, "r", encoding="utf-8") as f:
        overlay_source = json.load(f)

    if args.overlay_key is not None:
        if args.overlay_key not in overlay_source:
            print(
                f"error: key '{args.overlay_key}' not found in "
                f"{args.overlay_source_path}",
                file=sys.stderr,
            )
            return 1
        overlay = overlay_source[args.overlay_key]
    else:
        overlay = overlay_source

    target = load_json_or_none(args.target_path)

    if target is None:
        result = overlay
    else:
        try:
            result = shallow_merge(target, overlay)
        except TypeError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    with open(args.target_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run_tests.sh`
Expected: `== test_json_merge.sh ==` with no `FAIL:` lines, total failed count unchanged from before this task's run.

- [ ] **Step 5: Commit**

```bash
git add lib/json_merge.py tests/test_json_merge.sh
git commit -m "$(cat <<'EOF'
Add lib/json_merge.py: shallow JSON merge for settings/keybindings/mcp

No jq on this machine, so JSON reading/writing goes through Python.
Objects merge shallowly with the overlay winning per key; arrays
(keybindings.json) merge as a deduped union instead, since a
key-based merge doesn't make sense for a JSON array.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nb3bwco447DWeTGiyrmyZg
EOF
)"
```

---

## Task 4: Editor detection via process-tree walk + `product.json`

**Files:**
- Create: `lib/detect.sh`
- Create: `tests/test_detect.sh`

**Interfaces:**
- Consumes: `log_error`, `log_warn` from Task 2 (must be sourced first).
- Produces: `resolve_editor_paths(start_pid="$PPID")`, which sets four caller-visible variables — `EDITOR_APP_NAME`, `EDITOR_BIN`, `EDITOR_CONFIG_DIR`, `EDITOR_MCP_PATH` — each `""` if unresolved, and returns 1 if `EDITOR_APP_NAME` could not be determined at all. Also produces `find_electron_ancestor(pid, max_hops=20)` (echoes the editor's exe path or returns 1) and `read_product_json(path)` (echoes two lines: `applicationName`, `dataFolderName`). The low-level `_proc_exe_path(pid)` and `_proc_parent_pid(pid)` are separate, overridable functions — tests replace them wholesale to simulate a process tree without touching the real `/proc`. Task 6/7 call `resolve_editor_paths` and use its four output variables.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_detect.sh
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

rm -rf "$tmpdir"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run_tests.sh`
Expected: FAIL — `lib/detect.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
# lib/detect.sh - locate the running VS Code-family editor and derive its paths.
# Requires lib/log.sh to already be sourced (uses log_error/log_warn).

_proc_exe_path() {
    readlink -f "/proc/$1/exe" 2>/dev/null
}

_proc_parent_pid() {
    local stat
    stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
    stat="${stat##*)}"
    # shellcheck disable=SC2206
    local fields=($stat)
    echo "${fields[1]}"
}

find_electron_ancestor() {
    local pid="$1" max_hops="${2:-20}" hop=0 exe app_root
    while [[ "$pid" -gt 1 && "$hop" -lt "$max_hops" ]]; do
        exe="$(_proc_exe_path "$pid")"
        if [[ -n "$exe" ]]; then
            app_root="$(dirname "$exe")"
            if [[ -f "$app_root/resources/app/product.json" ]]; then
                echo "$exe"
                return 0
            fi
        fi
        pid="$(_proc_parent_pid "$pid")" || return 1
        [[ -z "$pid" ]] && return 1
        hop=$((hop + 1))
    done
    return 1
}

read_product_json() {
    python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('applicationName', ''))
print(d.get('dataFolderName', ''))
" "$1"
}

resolve_editor_paths() {
    local start_pid="${1:-$PPID}"
    EDITOR_APP_NAME=""
    EDITOR_BIN=""
    EDITOR_CONFIG_DIR=""
    EDITOR_MCP_PATH=""

    if [[ -z "${TERM_PROGRAM:-}" ]]; then
        log_error "TERM_PROGRAM não definido - rode este script de dentro do terminal integrado do editor"
        return 1
    fi

    local exe app_root product_json product_info app_name data_folder
    exe="$(find_electron_ancestor "$start_pid")"
    if [[ -z "$exe" ]]; then
        log_error "não foi possível localizar o processo do editor na árvore de processos"
        return 1
    fi

    app_root="$(dirname "$exe")"
    product_json="$app_root/resources/app/product.json"

    product_info="$(read_product_json "$product_json")" || {
        log_error "falha ao ler product.json em $product_json"
        return 1
    }
    app_name="$(sed -n '1p' <<<"$product_info")"
    data_folder="$(sed -n '2p' <<<"$product_info")"

    if [[ -z "$app_name" ]]; then
        log_error "product.json em $product_json não contém applicationName"
        return 1
    fi

    if [[ "$app_name" != "$TERM_PROGRAM" ]]; then
        log_warn "applicationName ($app_name) difere de TERM_PROGRAM ($TERM_PROGRAM) - seguindo com $app_name"
    fi

    EDITOR_APP_NAME="$app_name"

    if [[ -x "$app_root/bin/$app_name" ]]; then
        EDITOR_BIN="$app_root/bin/$app_name"
    elif command -v "$app_name" >/dev/null 2>&1; then
        EDITOR_BIN="$(command -v "$app_name")"
        log_warn "usando $EDITOR_BIN do PATH (layout $app_root/bin/$app_name não encontrado)"
    else
        log_error "não encontrei o binário de CLI do editor (tentei $app_root/bin/$app_name e o PATH)"
    fi

    if [[ -n "$data_folder" ]]; then
        EDITOR_CONFIG_DIR="$HOME/.config/$data_folder/User"
    else
        log_warn "product.json não contém dataFolderName - settings/keybindings serão pulados"
    fi

    EDITOR_MCP_PATH="$HOME/.$app_name/settings/mcp.json"

    return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run_tests.sh`
Expected: `== test_detect.sh ==` with no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/test_detect.sh
git commit -m "$(cat <<'EOF'
Add lib/detect.sh: locate the running editor via process tree + product.json

Walks the process ancestry from the shell that's running this script
to find the editor's own Electron process (identified by having a
resources/app/product.json sibling next to its executable), then
reads that product.json for applicationName/dataFolderName. This
works regardless of install method (tarball/snap/pacman/pamac) or
which VS Code-family editor it is, because it asks the already-running
process where it lives instead of guessing.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nb3bwco447DWeTGiyrmyZg
EOF
)"
```

---

## Task 5: Customizations data file

**Files:**
- Create: `customizations.json`
- Create: `tests/test_customizations_data.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `customizations.json` with top-level keys `extensions` (array of 17 extension ids), `font` (object with `name`, `version`, `download_url`, `install_dir`), `settings` (object, the full captured `settings.json` content), `keybindings` (array, the full captured `keybindings.json` content), `mcp` (object, the full captured `mcp.json` content). Task 6/7 read this file by path via the `CUSTOMIZATIONS_JSON` env var.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_customizations_data.sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run_tests.sh`
Expected: FAIL — `python3: can't open file '.../customizations.json'`.

- [ ] **Step 3: Write the data file**

```json
{
  "extensions": [
    "enkia.tokyo-night",
    "esbenp.prettier-vscode",
    "formulahendry.auto-close-tag",
    "mhutchie.git-graph",
    "mikestead.dotenv",
    "ms-azuretools.vscode-docker",
    "naumovs.color-highlight",
    "steoates.autoimport",
    "usernamehw.errorlens",
    "yzhang.markdown-all-in-one",
    "ms-azuretools.vscode-containers",
    "redhat.vscode-yaml",
    "dbaeumer.vscode-eslint",
    "wallabyjs.console-ninja",
    "pkief.material-icon-theme",
    "astro-build.astro-vscode",
    "eamodio.gitlens"
  ],
  "font": {
    "name": "JetBrains Mono",
    "version": "2.304",
    "download_url": "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip",
    "install_dir": "JetBrainsMono"
  },
  "settings": {
    "workbench.colorTheme": "Tokyo Night Storm",
    "editor.inlineSuggest.enabled": true,
    "workbench.iconTheme": "material-icon-theme",
    "editor.fontFamily": "JetBrains Mono, Menlo, Monaco, 'Courier New', monospace",
    "editor.fontLigatures": true,
    "editor.fontSize": 16,
    "javascript.updateImportsOnFileMove.enabled": "always",
    "workbench.startupEditor": "none",
    "console-ninja.featureSet": "Community",
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "extensions.ignoreRecommendations": true,
    "window.newWindowProfile": "Default",
    "kiroAgent.agentAutonomy": "Autopilot",
    "accessibility.signals.lineHasBreakpoint": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.chatEditModifiedFile": {"sound": "off"},
    "accessibility.signals.chatRequestSent": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.chatResponseReceived": {"sound": "off"},
    "accessibility.signals.chatUserActionRequired": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.clear": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.codeActionApplied": {"sound": "off"},
    "accessibility.signals.codeActionTriggered": {"sound": "off"},
    "accessibility.signals.onDebugBreak": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.diffLineDeleted": {"sound": "off"},
    "accessibility.signals.diffLineInserted": {"sound": "off"},
    "accessibility.signals.diffLineModified": {"sound": "off"},
    "accessibility.signals.editsKept": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.positionHasError": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.lineHasError": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.lineHasFoldedArea": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.lineHasInlineSuggestion": {"sound": "off"},
    "accessibility.signals.nextEditSuggestion": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.noInlayHints": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.notebookCellCompleted": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.notebookCellFailed": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.progress": {"sound": "off", "announcement": "off"},
    "accessibility.signals.taskCompleted": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.taskFailed": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.terminalBell": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.terminalCommandFailed": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.terminalCommandSucceeded": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.terminalQuickFix": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.editsUndone": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.voiceRecordingStarted": {"sound": "off"},
    "accessibility.signals.voiceRecordingStopped": {"sound": "off"},
    "accessibility.signals.positionHasWarning": {"sound": "off", "announcement": "auto"},
    "accessibility.signals.lineHasWarning": {"sound": "off", "announcement": "auto"},
    "typescript.updateImportsOnFileMove.enabled": "always",
    "kiroAgent.trustedTools": ["web_fetch", "remote_web_search"],
    "redhat.telemetry.enabled": false,
    "kiroAgent.modelSelection": "auto",
    "security.workspace.trust.untrustedFiles": "open",
    "terminal.integrated.shellIntegration.enabled": false,
    "editor.accessibilitySupport": "off"
  },
  "keybindings": [
    {
      "key": "ctrl+;",
      "command": "editor.action.commentLine",
      "when": "textInputFocus && !editorReadonly"
    },
    {
      "key": "ctrl+;",
      "command": "editor.action.blockComment",
      "when": "textInputFocus && !editorReadonly"
    }
  ],
  "mcp": {
    "mcpServers": {
      "fetch": {
        "command": "uvx",
        "args": ["mcp-server-fetch"],
        "env": {},
        "disabled": true,
        "autoApprove": []
      },
      "storybook-mcp": {
        "type": "http",
        "url": "http://localhost:6006/mcp"
      }
    },
    "powers": {
      "mcpServers": {
        "power-figma-figma": {
          "type": "http",
          "url": "https://mcp.figma.com/mcp",
          "autoApprove": ["get_screenshot", "get_design_context"],
          "disabledTools": []
        }
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run_tests.sh`
Expected: `== test_customizations_data.sh ==` with no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add customizations.json tests/test_customizations_data.sh
git commit -m "$(cat <<'EOF'
Add customizations.json: static snapshot of the local Kiro setup

Extensions, font, settings.json, keybindings.json and mcp.json content
captured from the local Kiro install on 2026-09-03. Treated as a
single universal profile applied to whatever editor is detected, per
the user's explicit choice not to split per-editor profiles.

Dropped kiroAgent.trustedCommands and chat.tools.terminal.autoApprove
on purpose - both are agent auto-approved shell command allowlists
from the source install and the user asked not to carry those over.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nb3bwco447DWeTGiyrmyZg
EOF
)"
```

---

## Task 6: Apply steps (extensions, font, settings, mcp)

**Files:**
- Create: `lib/apply.sh`
- Create: `tests/test_apply.sh`

**Interfaces:**
- Consumes: `log_info/log_ok/log_warn/log_error`, `record_step`, `print_summary` (Task 2, must be sourced first); `python3 lib/json_merge.py` CLI (Task 3); `customizations.json` shape (Task 5) via the `CUSTOMIZATIONS_JSON` env var.
- Produces: `install_extensions(editor_bin)`, `install_font()`, `apply_settings(config_dir)`, `apply_mcp(mcp_path)` — each records its own step outcome and never returns a failure that should stop the caller. Overridable low-level `_download_file(url, dest)` and `_extract_zip(zip_path, dest_dir)` (same override-for-testing pattern as Task 4). Reads `FONT_INSTALL_DIR` env var (default `$HOME/.local/share/fonts/JetBrainsMono`). Task 7 calls all four functions in sequence.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_apply.sh
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

rm -rf "$tmpdir"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run_tests.sh`
Expected: FAIL — `lib/apply.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
# lib/apply.sh - install extensions/font, apply settings/keybindings/mcp.
# Requires lib/log.sh already sourced. Reads CUSTOMIZATIONS_JSON.

FONT_INSTALL_DIR="${FONT_INSTALL_DIR:-$HOME/.local/share/fonts/JetBrainsMono}"
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_download_file() {
    curl -fsSL -o "$2" "$1"
}

_extract_zip() {
    unzip -oq "$1" -d "$2"
}

install_extensions() {
    local editor_bin="$1"
    if [[ -z "$editor_bin" ]]; then
        log_warn "pulando instalação de extensões: nenhum binário de editor resolvido"
        record_step "extensões" "SKIPPED"
        return 0
    fi

    local ids
    ids="$(python3 -c "
import json
d = json.load(open('$CUSTOMIZATIONS_JSON'))
print('\n'.join(d['extensions']))
")"

    local ok=0 fail=0 id
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        if "$editor_bin" --install-extension "$id" >>"$LOG_FILE" 2>&1; then
            log_ok "extensão instalada: $id"
            ok=$((ok + 1))
        else
            log_error "falha ao instalar extensão: $id"
            fail=$((fail + 1))
        fi
    done <<<"$ids"

    if [[ "$fail" -eq 0 ]]; then
        record_step "extensões: $ok ok, $fail falharam" "OK"
    else
        record_step "extensões: $ok ok, $fail falharam" "AVISO"
    fi
    return 0
}

install_font() {
    if compgen -G "$FONT_INSTALL_DIR/*.ttf" >/dev/null 2>&1; then
        log_ok "fonte já presente em $FONT_INSTALL_DIR, pulando download"
        record_step "fonte" "OK"
        return 0
    fi

    local name url tmpdir zip_path
    name="$(python3 -c "import json; print(json.load(open('$CUSTOMIZATIONS_JSON'))['font']['name'])")"
    url="$(python3 -c "import json; print(json.load(open('$CUSTOMIZATIONS_JSON'))['font']['download_url'])")"

    tmpdir="$(mktemp -d)"
    zip_path="$tmpdir/font.zip"

    if ! _download_file "$url" "$zip_path" >>"$LOG_FILE" 2>&1; then
        log_warn "falha ao baixar a fonte $name de $url - pulando"
        record_step "fonte" "AVISO"
        rm -rf "$tmpdir"
        return 1
    fi

    mkdir -p "$FONT_INSTALL_DIR"
    if ! _extract_zip "$zip_path" "$tmpdir/extracted" >>"$LOG_FILE" 2>&1; then
        log_warn "falha ao extrair a fonte $name - pulando"
        record_step "fonte" "AVISO"
        rm -rf "$tmpdir"
        return 1
    fi

    find "$tmpdir/extracted" -iname "*.ttf" -exec cp {} "$FONT_INSTALL_DIR/" \;

    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$FONT_INSTALL_DIR" >>"$LOG_FILE" 2>&1
    fi

    rm -rf "$tmpdir"
    log_ok "fonte $name instalada em $FONT_INSTALL_DIR"
    record_step "fonte" "OK"
    return 0
}

_apply_json_key() {
    local config_dir="$1" filename="$2" overlay_key="$3" step_label="$4"
    local target="$config_dir/$filename"

    mkdir -p "$config_dir"

    if [[ -f "$target" ]]; then
        cp "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
    fi

    if python3 "$SCRIPT_LIB_DIR/json_merge.py" "$target" "$CUSTOMIZATIONS_JSON" --overlay-key "$overlay_key" >>"$LOG_FILE" 2>&1; then
        log_ok "$step_label aplicado em $target"
        record_step "$step_label" "OK"
        return 0
    else
        log_error "falha ao aplicar $step_label em $target"
        record_step "$step_label" "ERRO"
        return 1
    fi
}

apply_settings() {
    local config_dir="$1"
    if [[ -z "$config_dir" ]]; then
        log_warn "pulando settings/keybindings: config_dir não resolvido"
        record_step "settings" "SKIPPED"
        record_step "keybindings" "SKIPPED"
        return 0
    fi
    _apply_json_key "$config_dir" "settings.json" "settings" "settings"
    _apply_json_key "$config_dir" "keybindings.json" "keybindings" "keybindings"
}

apply_mcp() {
    local mcp_path="$1"
    if [[ -z "$mcp_path" ]]; then
        log_warn "pulando mcp.json: mcp_path não resolvido"
        record_step "mcp" "SKIPPED"
        return 0
    fi
    local mcp_dir
    mcp_dir="$(dirname "$mcp_path")"
    _apply_json_key "$mcp_dir" "$(basename "$mcp_path")" "mcp" "mcp"
    log_info "servidores MCP que exigem login (ex: figma) precisam de autenticação manual depois"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run_tests.sh`
Expected: `== test_apply.sh ==` with no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add lib/apply.sh tests/test_apply.sh
git commit -m "$(cat <<'EOF'
Add lib/apply.sh: install extensions/font, apply settings/keybindings/mcp

Every step is isolated and always records an outcome (OK/AVISO/ERRO/
SKIPPED) instead of aborting: one failed extension install doesn't
block the rest, a failed font download is a warning not a crash, and
settings/keybindings/mcp are always backed up before being
overwritten.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nb3bwco447DWeTGiyrmyZg
EOF
)"
```

---

## Task 7: Entry point and README

**Files:**
- Create: `install-editor-setup.sh`
- Create: `README.md`
- Create: `tests/test_entrypoint.sh`

**Interfaces:**
- Consumes: `resolve_editor_paths` (Task 4); `install_extensions`, `install_font`, `apply_settings`, `apply_mcp` (Task 6); `record_step`, `print_summary`, `log_info` (Task 2).
- Produces: `main()`, wired to run automatically only when the script is executed directly (`bash install-editor-setup.sh` or `./install-editor-setup.sh`) — not when sourced, which is what makes it testable.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_entrypoint.sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run_tests.sh`
Expected: FAIL — `install-editor-setup.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
# install-editor-setup.sh - apply personal extensions/font/settings/
# keybindings/mcp to whichever VS Code-family editor's integrated
# terminal this is run from.
#
# Usage: from inside the target editor's own integrated terminal:
#   bash install-editor-setup.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
    CUSTOMIZATIONS_JSON="${CUSTOMIZATIONS_JSON:-$SCRIPT_DIR/customizations.json}"
    LOG_FILE="${LOG_FILE:-$HOME/.editor-setup-install.log}"
    export CUSTOMIZATIONS_JSON LOG_FILE

    log_info "iniciando instalação de customizações do editor"

    resolve_editor_paths || true

    if [[ -n "$EDITOR_APP_NAME" ]]; then
        log_info "editor detectado: $EDITOR_APP_NAME"
        record_step "detecção do editor ($EDITOR_APP_NAME)" "OK"
    else
        record_step "detecção do editor" "ERRO"
    fi

    install_extensions "$EDITOR_BIN"
    install_font
    apply_settings "$EDITOR_CONFIG_DIR"
    apply_mcp "$EDITOR_MCP_PATH"

    print_summary
    log_info "log completo em $LOG_FILE"
}

# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck source=lib/apply.sh
source "$SCRIPT_DIR/lib/apply.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
```

```markdown
# editor-setup

Instala extensões, fonte (JetBrains Mono), settings, keybindings e
configuração de MCP servers num editor da família VS Code (Kiro, VS
Code, forks), a partir do snapshot capturado da instalação local do
Kiro em `customizations.json`.

## Uso

Abra o terminal integrado do editor que você quer configurar e rode:

    bash install-editor-setup.sh

O script detecta o editor automaticamente a partir do terminal em que
está rodando (não funciona se executado fora do terminal integrado de
um editor da família VS Code). Ele não interrompe no primeiro erro:
cada etapa (extensões, fonte, settings, keybindings, mcp) roda de
forma independente, e o resumo no final mostra o que funcionou, o que
falhou e o que foi pulado.

Log completo em `~/.editor-setup-install.log`.

## Requisitos

bash, python3, curl, unzip, fontconfig (`fc-cache`).

## Limitações conhecidas

- Servidores MCP que exigem login interativo (ex. Figma) precisam de
  autenticação manual depois de aplicado o `mcp.json`.
- `customizations.json` é um snapshot estático capturado em
  2026-09-03 a partir da instalação local do Kiro - não é
  resincronizado automaticamente se você mudar extensões/settings
  depois.
- Validado até agora apenas contra uma instalação manual (tarball) do
  Kiro. Comportamento em instalações via snap/pacman/pamac ainda não
  foi testado - ver `docs/superpowers/specs/` para o design da
  detecção.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run_tests.sh`
Expected: `== test_entrypoint.sh ==` with no `FAIL:` lines, final line `Total: N run, 0 failed` across the whole suite.

- [ ] **Step 5: Make it executable and commit**

```bash
chmod +x install-editor-setup.sh
git add install-editor-setup.sh README.md tests/test_entrypoint.sh
git commit -m "$(cat <<'EOF'
Add install-editor-setup.sh entry point and README

Wires detection, extension/font install, and settings/keybindings/mcp
application into one ordered flow that always runs every step and
never aborts partway through. main() only auto-runs when the script
is executed directly, so the entry point stays testable by sourcing
it and overriding the low-level network/proc functions.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nb3bwco447DWeTGiyrmyZg
EOF
)"
```

---

## Manual validation (not automated here, per user instruction)

Once this plan is implemented, the user will separately verify, on real
installs this sandbox doesn't have:

- Kiro/VS Code/a fork installed via snap - does `/proc/<pid>/exe` resolve
  to a usable path given snap's confinement, and does the
  `app_root/bin/<name>` guess hold or fall through to the PATH fallback?
- The same for a pacman/AUR install and a pamac-driven install.
- A real font download from the pinned JetBrains Mono 2.304 GitHub URL
  (this plan never exercises the real network call).
- Running the script twice in a row on the same install, to confirm the
  idempotency claims (no duplicate extension installs, font step skips
  cleanly, settings/mcp backups don't pile up unexpectedly).
