local M = {}

local watcher = nil
local reload_timer = nil

local function schedule_reload()
  if reload_timer then
    reload_timer:stop()
  end

  reload_timer = hs.timer.doAfter(0.3, function()
    hs.reload()
  end)
end

function M.init(config)
  local reload_config = (config.reload or {})
  local hotkey = reload_config.hotkey or { { "cmd", "alt", "ctrl" }, "R" }

  hs.hotkey.bind(hotkey[1], hotkey[2], function()
    hs.reload()
  end)

  if reload_config.watchConfigDir ~= false then
    watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function()
      schedule_reload()
    end)
    watcher:start()
  end
end

return M

