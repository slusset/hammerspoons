local M = {}
local script_runner = require("lib.script_runner")

local function run_action(action, cfg)
  if type(action) ~= "table" or not action.type then
    hs.alert.show("Invalid action config")
    return
  end

  if action.type == "app" and action.name then
    hs.application.launchOrFocus(action.name)
    return
  end

  if action.type == "url" and action.url then
    hs.urlevent.openURL(action.url)
    return
  end

  if action.type == "shell" and action.command then
    script_runner.run_shell(action.command, cfg.notifyOnShellFinish == true)
    return
  end

  if action.type == "hs" and action.command then
    if action.command == "reload" then
      hs.reload()
      return
    end
    if action.command == "console" then
      hs.toggleConsole()
      return
    end
    if action.command == "lockScreen" then
      hs.caffeinate.lockScreen()
      return
    end
  end

  if action.type == "noop" then
    return
  end

  hs.alert.show("Unsupported action: " .. tostring(action.type))
end

function M.init(config)
  local cfg = config.keystrokes or {}
  if cfg.enabled == false then
    return
  end

  for _, binding in ipairs(cfg.hotkeys or {}) do
    if binding.mods and binding.key and binding.action then
      hs.hotkey.bind(binding.mods, binding.key, function()
        run_action(binding.action, cfg)
      end)
    end
  end
end

return M

