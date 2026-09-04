# A script for setup editor settings

Installs extensions, fonts, settings, and keybindings into a VS
Code-family editor (Kiro, VS Code, or any fork), from the snapshot
captured in `customizations.json`.

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
