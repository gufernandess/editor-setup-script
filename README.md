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
terminal of a VS Code-family editor). It never stops on the first
error: each step (extensions, font, settings, keybindings) runs
independently, and the summary at the end shows what succeeded, what
failed, and what was skipped.

Full log at `~/.editor-setup-install.log`.

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
