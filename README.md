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
