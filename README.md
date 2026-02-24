# Hammerspoon Automation Workspace

This repo is a shared, modular Hammerspoon setup designed to replace:

- Rectangle window tiling
- BetterTouchTool keystroke interception and script execution
- Amphetamine-style "stay awake" automation for external monitor workflows

## Layout

- `init.lua`: entrypoint, loads modules
- `lib/`: shared helpers
- `modules/`: focused automation modules
- `config/defaults.lua`: committed default settings
- `config/overrides/common.lua`: shared overrides for both laptops
- `config/overrides/hosts/<hostname>.lua`: per-machine overrides keyed by hostname
- `config/overrides/hosts/example_host.lua.example`: host override template
- `config/local.lua`: local-only overrides (gitignored)
- `scripts/`: shell scripts callable from hotkeys
- `bin/install`: symlink repo to `~/.hammerspoon`
- `dotfiles/tmux/.tmux.conf`: shared tmux config
- `bin/install-tmux`: symlink tmux config to `~/.tmux.conf`

## Install

```bash
./bin/install
```

Then open/reload Hammerspoon.

Install tmux config:

```bash
./bin/install-tmux
```

Install global CLI links for Outlook helper scripts:

```bash
./bin/install-scripts
```

This creates these commands in `~/.local/bin`:

- `outlook-mail`
- `outlook-gui`
- `outlook-ax`

Use `--bin-dir PATH` to install elsewhere and `--force` to replace existing paths.

## How configuration layers merge

Load order (last wins):

1. `config/defaults.lua`
2. `config/overrides/common.lua`
3. `config/overrides/hosts/<your-hostname>.lua`
4. `config/local.lua`

Hostname key is normalized to lowercase with non-alphanumeric chars replaced by `_`.

## Migration mapping

### Rectangle replacement

Use `modules/window_tiling.lua`.
Default keybinds are in `config/defaults.lua` under `windowTiling.hotkeys`.

Supported actions include:

- `left`, `right`, `top`, `bottom`
- `topLeft`, `topRight`, `bottomLeft`, `bottomRight`
- `center`, `maximize`, `maximizeHeight`
- `larger`, `smaller`, `restore`
- `nextScreen`, `previousScreen`

### BetterTouchTool replacement

Use `modules/keystrokes.lua`.
Define bindings in `keystrokes.hotkeys` with actions:

- `app`: launch/focus app
- `url`: open URL
- `shell`: run command in `zsh -lc`
- `hs`: built-in Hammerspoon action (`reload`, `console`, `lockScreen`)
- `noop`: intercept and suppress keystroke only

Example:

```lua
{
  mods = { "ctrl", "alt", "cmd" },
  key = "I",
  description = "Open iTerm",
  action = { type = "app", name = "iTerm" }
}
```

### Amphetamine-style awake behavior

Use `modules/awake.lua`.
It enables idle sleep prevention when your configured conditions are met (by default: external display attached and AC power present).

Tune behavior via `awake` settings in config.
Useful settings:

- `requireClamshell`: require external-only display state
- `preventDisplaySleep`: keep displays awake too (default `false`)
- `manualToggleHotkey`: toggle manual awake override (default `ctrl`+`alt`+`cmd`+`A`)

### Jiggler-style activity

Use `modules/jiggler.lua`.
Default behavior is a 5-minute `zen` poke with no visible cursor movement.
Useful settings:

- `intervalSeconds`: jiggle/poke interval (`300` = 5 minutes)
- `mode`: `zen` (invisible) or `mouse` (1px move + restore)
- `toggleHotkey`: pause/resume jiggler (default `ctrl`+`alt`+`cmd`+`J`)

## Recommended workflow across two laptops

1. Keep shared behavior in `config/overrides/common.lua`.
2. Put laptop-specific differences in `config/overrides/hosts/<hostname>.lua`.
3. Keep secrets and temporary experiments in `config/local.lua`.
4. Add new automation as one module per concern under `modules/`.
5. Keep module defaults in `config/defaults.lua` and avoid hard-coding paths.

## First-time setup per laptop

1. Run `./bin/install`.
2. Determine normalized hostname in Hammerspoon console:
   `string.lower(hs.host.localizedName()):gsub("[^a-z0-9]", "_")`
3. Copy `config/overrides/hosts/example_host.lua.example` to
   `config/overrides/hosts/<normalized-hostname>.lua`.
4. Add machine-specific overrides in that file.

## Outlook GUI CLI script

Use `scripts/outlook_gui.sh` when an agent needs to drive Outlook from CLI on macOS.

Examples:

```bash
scripts/outlook_gui.sh focus
scripts/outlook_gui.sh new-message
scripts/outlook_gui.sh compose --to "person@example.com" --subject "Status" --body "Draft body"
scripts/outlook_gui.sh compose --to "person@example.com" --subject "Status" --body "Ready to send" --send
scripts/outlook_gui.sh compose --to "person@example.com" --subject "Status" --body "Hello" --pre-to-tabs 1
scripts/outlook_gui.sh compose --to "person@example.com" --subject "Status" --body "Hello" --step-wait 0.15
scripts/outlook_gui.sh compose-ax --to "person@example.com" --subject "Status" --body "Hello"
scripts/outlook_gui.sh compose-ax --to "person@example.com" --subject "Status" --body "Hello" --send --send-mode button
scripts/outlook_gui.sh search --query "incident 12345"
scripts/outlook_gui.sh send-current
scripts/outlook_gui.sh send-current --method button
```

Compose note:

- `--pre-to-tabs` controls how many initial `Tab` presses happen before filling the `To:` value.
- Default is `0` because current Outlook compose windows start focused in `To:`.
- Set `1` only if your compose flow starts focus on `From:` or another control first.
- `--step-wait` (default `0.12`) adds a short delay between tabs/pastes so Outlook focus updates reliably.
- `compose-ax` uses Hammerspoon AX identifiers (`toTextField`, `subjectTextField`) and is generally more reliable than tab-count targeting.
- AX sending supports `--send-mode keystroke` (Cmd+Return) or `--send-mode button` (click Send via accessibility).
- `send-current --method button` clicks the visible Send button via AX; `--method keystroke` uses Cmd+Return.

Requirements:

- Microsoft Outlook installed
- Calling terminal/agent allowed under macOS `System Settings > Privacy & Security > Accessibility`
- Outlook automation allowed under `System Settings > Privacy & Security > Automation`

## Outlook AX inspection via Hammerspoon CLI

Use `scripts/outlook_ax.sh` to inspect Outlook compose accessibility elements and field counts.

Examples:

```bash
scripts/outlook_ax.sh counts
scripts/outlook_ax.sh dump --depth 7 --max-nodes 1000
scripts/outlook_ax.sh focused
```

Expected workflow for field-count issues:

1. Open Outlook compose window and focus it.
2. Run `scripts/outlook_ax.sh counts` to see editable candidates.
3. Run `scripts/outlook_ax.sh dump` for full tree when counts look wrong.
4. Adjust `scripts/outlook_gui.sh compose --pre-to-tabs N` based on findings.

Requirements:

- Hammerspoon running with this config loaded
- `hs` CLI installed and in `PATH`
- `hs.ipc` available (this repo now loads `modules/ipc.lua` by default)

## Outlook mailbox CLI (AppleScript model)

Use `scripts/outlook_mail.sh` to read/search/summarize/prioritize messages without Graph API.

Examples:

```bash
scripts/outlook_mail.sh search --folder inbox --topic "incident" --from "alerts@"
scripts/outlook_mail.sh search --folder sent --to "person@example.com" --limit 25
scripts/outlook_mail.sh read --id 123456
scripts/outlook_mail.sh summarize --id 123456
scripts/outlook_mail.sh prioritize --folder inbox --unread --top 15 --vip "manager@vumc.org,lead@vumc.org"
```

Folder options:

- Shortcut names: `inbox`, `sent`, `drafts`, `deleted`, `junk`, `outbox`
- Or pass an exact Outlook mail-folder name.

Work-laptop scope:

- Default scope is `work`.
- Set host allowlist once:
  `export OUTLOOK_WORK_HOSTS="work_laptop_host_name"`
- Run on allowed hosts only:
  `scripts/outlook_mail.sh search --folder inbox`
- Bypass scope for testing:
  `scripts/outlook_mail.sh search --folder inbox --scope any`
