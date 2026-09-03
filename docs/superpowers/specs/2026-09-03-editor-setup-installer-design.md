# Editor Setup Installer — Design

## Problem

The user has a locally customized Kiro IDE install (extensions, font,
editor settings, keybindings, MCP server config) and wants a script
that reproduces that setup. The script should not assume the target
editor is Kiro specifically (it could be VS Code or any other VS
Code-family fork), and should not assume how that editor was
installed (tarball, snap, pacman, pamac/AUR).

## Non-goals

- Testing/validating against snap, pacman, or pamac installs in this
  session — no such install is available locally. The user will
  validate manually later.
- Building a real editor extension (`.vsix`). Considered as Approach C
  and rejected as disproportionate effort for a personal dotfiles
  tool (see Approaches below).
- Automating OAuth/login for MCP servers that need it (e.g. Figma).
- Live-syncing from the running editor on every execution. This is a
  static snapshot captured from the current Kiro install; if the user
  changes extensions/settings later, the script's data file becomes
  stale until edited by hand.
- Per-editor customization profiles. All customizations are treated as
  universal and applied to whatever editor is detected; settings keys
  that don't apply to a given editor (e.g. `kiroAgent.*` outside Kiro)
  are simply inert there.

## Approaches considered

**A — Run from the target editor's own integrated terminal, self-detect
via `product.json` (chosen).** VS Code-family editors set
`$TERM_PROGRAM` in their integrated terminal to their
`product.json`'s `applicationName`. Walking the process tree from the
running shell finds the editor's own Electron binary regardless of
install method, and reading `product.json` next to that binary yields
`applicationName` and `dataFolderName` — enough to derive the CLI
binary, user config dir, and MCP config path generically, with no
install-method-specific or per-editor-specific branches.

**B — Standalone script, explicit `--editor` flag, per-install-method
heuristics.** Works without the editor running, but needs bespoke
detection code for each of tarball/snap/pacman/pamac and each editor —
the exact detection burden Approach A avoids.

**C — Real VS Code extension (`.vsix`).** Cleanest use of editor APIs,
but requires packaging and sideloading before it can run at all —
disproportionate for this tool's scope.

Approach A was chosen for its minimal implementation cost and because
it generalizes across editors and install methods for free.

## Architecture

### Repository layout

```
~/projects/editor-setup/
├── install-editor-setup.sh   # entry point
├── lib/
│   ├── log.sh                 # logging helpers
│   ├── detect.sh               # locate running editor + derive paths
│   └── apply.sh                 # install extensions/font/settings/mcp
├── customizations.json          # single data file (see below)
└── README.md
```

### Detection (`lib/detect.sh`)

1. Read `$TERM_PROGRAM`. If empty, log an error explaining that the
   script should be run from inside the target editor's integrated
   terminal, and treat all of `editor_bin` / `config_dir` / `mcp_path`
   as unresolved (empty). This does not abort the script: the font
   step does not depend on editor detection at all, and runs
   regardless.
2. Walk the process ancestry starting at `$PPID` (via `/proc/<pid>/exe`
   and `/proc/<pid>/stat` for the next ancestor), looking for the
   first ancestor whose resolved executable path has a sibling
   `resources/app/product.json`. This skips intermediate processes
   (pty host, shell wrappers) and finds the editor's own Electron
   process regardless of how it was installed.
3. Parse that `product.json` for `applicationName` (cross-checked
   against `$TERM_PROGRAM`) and `dataFolderName`.
4. Derive, independently of one another:
   - `editor_bin` — the CLI binary near the resolved install dir, used
     for `--install-extension`.
   - `config_dir` — `~/.config/<dataFolderName>/User`, used for
     `settings.json` / `keybindings.json`.
   - `mcp_path` — `~/.<applicationName>/settings/mcp.json`, the
     convention observed in the local Kiro install, applied
     generically.
5. Each of the three is allowed to fail independently. A failure
   disables only the apply steps that depend on it (see below) and is
   logged as a warning — it does not abort the rest of the script.

### Logging and resilience (`lib/log.sh`, applies script-wide)

- `log_info` / `log_ok` / `log_warn` / `log_error`: timestamped,
  prefixed (`[OK]`, `[AVISO]`, `[ERRO]`) lines, printed to stdout and
  appended to `~/.editor-setup-install.log`.
- No global `set -e`. Every step is its own function; the caller
  checks its return code, logs the outcome, and always proceeds to
  the next step regardless of failure.
- A final summary block lists every step's outcome (OK / WARN /
  ERROR / SKIPPED) so the user can see the whole run at a glance
  without reading the full log.

### Apply (`lib/apply.sh`)

- **Extensions** — loop over `customizations.json`'s extension id
  list; each `"$editor_bin" --install-extension "$id"` runs in
  isolation, success/failure logged per extension, one failure never
  blocks the rest.
- **Font (JetBrains Mono)** — idempotent: downloads the pinned 2.304
  release from GitHub to a temp dir, extracts fonts into
  `~/.local/share/fonts/JetBrainsMono/`, runs `fc-cache -f`. Skips the
  download if the target files already exist. Network failure is
  logged as a warning and the step is skipped, not fatal.
- **Settings/keybindings** — runs only if `config_dir` resolved.
  Backs up any existing `settings.json` / `keybindings.json` to
  `<file>.bak.<timestamp>` before writing. Applies a shallow merge:
  keys from `customizations.json` overwrite matching keys at the
  destination; keys already present at the destination but absent
  from `customizations.json` are preserved.
- **MCP config** — runs only if `mcp_path` resolved. Same
  backup-then-shallow-merge pattern, applied to the `mcpServers` and
  `powers` keys. The final summary notes that servers requiring
  interactive auth (e.g. Figma) need manual login afterward — this is
  not automated.

### `customizations.json`

One data file holding everything captured from the current Kiro
install: extension id list, font name/version, the full
`settings.json` content, `keybindings.json` content, and `mcp.json`
content. No per-editor split — applied as-is regardless of which
editor was detected.

### Entry point (`install-editor-setup.sh`)

Sources `lib/log.sh`, `lib/detect.sh`, `lib/apply.sh`; runs, in order:
detect → install_extensions → install_font → apply_settings →
apply_mcp → print_summary. Every step runs even if an earlier one
failed or was skipped, except where a step's own precondition
(`config_dir` / `mcp_path`) was not met.

### Idempotency

Running the script twice must not duplicate or silently clobber
anything: extension installs are no-ops when already installed (the
editor CLI itself handles this), the font step is skipped once
present, and settings/MCP writes always version a backup before
overwriting.

## Testing

Deferred. This session has no snap, pacman, or pamac Kiro/VS Code
install to validate against — only the local tarball install. The
user will test the other install methods manually later.
