# A script for setup editor settings

Installs extensions, fonts, settings, and keybindings into a VS
Code-family editor (Kiro, VS Code, or any fork), from the snapshot
captured in `customizations.json`.

This is a **Linux-only** script — it relies on `/proc` to locate the
running editor's process and on Linux conventions (`~/.config`,
fontconfig) to place settings and fonts. It doesn't work on macOS or
Windows.

## Getting started

Clone the repo, then run the script from inside the editor you want
to configure:

```
git clone <this-repo-url>
cd editor-setup
```

Open the integrated terminal of the editor you want to configure and
run it from there:

```
bash install-editor-setup.sh
```

## Usage

The script detects the running editor automatically from the
terminal it's running in (it won't work if run outside the integrated
terminal of a VS Code-family editor). It then **closes that editor
process first**, applies everything (extensions, font, settings,
keybindings) while it's shut down, and relaunches it — each step still
runs independently and never stops on the first error. Closing it
first, instead of applying changes to the live process and restarting
afterward, avoids the editor's own startup/shutdown routines racing
with the script and overwriting `settings.json`/`keybindings.json`
right after they're written.

This is meant to be run once, before starting any work, so it doesn't
try to preserve open tabs/windows: whatever the editor's own session
restore does on a normal restart is what you'll get back.

Since the editor closes almost immediately, most of the run happens
after the terminal is gone — check `~/.editor-setup-install.log` for
the full log and final summary.

## Requirements

- bash
- python3
- curl
- unzip
- fontconfig (`fc-cache`)

## Caveats

- `settings.json` and `keybindings.json` are **fully replaced**, not
  merged and without a backup — any customization already in those
  files that isn't in `customizations.json` is lost for good.
- MCP server configuration isn't synced by this script — the format
  varies too much from editor to editor to snapshot generically.
- `customizations.json` is a static snapshot — it isn't resynced
  automatically if you change extensions/settings later.
- The editor's config directory is resolved by trying, in order:
  `$XDG_CONFIG_HOME/<data folder>/User` (if set), `~/.config/<data
  folder>/User`, then any matching Flatpak (`~/.var/app/*/config/...`)
  or Snap (`~/snap/*/current/.config/...`) sandbox path that already
  exists. If none exist yet, it falls back to `~/.config/<data
  folder>/User` (or `$XDG_CONFIG_HOME` if set).
