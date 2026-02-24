local config = require("lib.config").load()
hs.logger.defaultLogLevel = config.logLevel or "info"

local log = hs.logger.new("init", config.logLevel or "info")
local modules = {
  "modules.reload",
  "modules.ipc",
  "modules.outlook_ax",
  "modules.window_tiling",
  "modules.keystrokes",
  "modules.awake",
  "modules.jiggler",
}

for _, module_name in ipairs(modules) do
  local ok_module, module = pcall(require, module_name)
  if not ok_module then
    log.ef("Failed to load module %s: %s", module_name, module)
  elseif type(module.init) == "function" then
    local ok_init, err = pcall(module.init, config)
    if not ok_init then
      log.ef("Failed to initialize module %s: %s", module_name, err)
    else
      log.i(string.format("Loaded %s", module_name))
    end
  end
end

if config.notifications and config.notifications.enabled then
  hs.notify.new({
    title = "Hammerspoon",
    informativeText = "Config loaded",
  }):send()
end
