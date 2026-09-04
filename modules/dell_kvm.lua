local M = {}

local screen_watcher = nil
local connect_timer = nil
local switch_task = nil
local connect_task = nil
local hotkey = nil

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function notify(cfg, title, text)
  if cfg.showNotifications == false then
    return
  end

  hs.notify.new({
    title = title,
    informativeText = text,
  }):send()
end

local function display_is_attached(cfg)
  local needle = string.lower(cfg.displayNameContains or "")
  if needle == "" then
    return false
  end

  for _, screen in ipairs(hs.screen.allScreens()) do
    local name = string.lower(screen:name() or "")
    if name:find(needle, 1, true) then
      return true
    end
  end

  return false
end

local function script_arguments(action, cfg)
  local inputs = cfg.inputs or {}
  local args = {
    hs.configdir .. "/scripts/switch-dell-monitor.sh",
    action,
    "--display", tostring(cfg.displayNumber or 1),
    "--input-a", tostring(inputs[1] or 15),
    "--input-b", tostring(inputs[2] or 25),
    "--keyfob-volume-uuid", cfg.keyfobVolumeUUID or "",
    "--blueutil", cfg.bluetoothBinary or "/opt/homebrew/bin/blueutil",
    "--m1ddc", cfg.m1ddcBinary or "/opt/homebrew/bin/m1ddc",
    "--connect-attempts", tostring(cfg.connectAttempts or 5),
  }

  for _, device in ipairs(cfg.bluetoothDevices or {}) do
    local address = type(device) == "table" and device.address or device
    if type(address) == "string" and address ~= "" then
      table.insert(args, "--device")
      table.insert(args, address)
    end
  end

  return args
end

local function result_text(std_out, std_err, fallback)
  local out = trim(std_out)
  local err = trim(std_err)
  if err ~= "" then
    return err
  end
  if out ~= "" then
    return out
  end
  return fallback
end

local function run_action(action, cfg)
  local active_task = action == "switch" and switch_task or connect_task
  if active_task and active_task:isRunning() then
    if action == "switch" then
      notify(cfg, "Dell KVM", "A monitor switch is already running.")
    end
    return
  end

  local task
  task = hs.task.new("/bin/bash", function(exit_code, std_out, std_err)
    if action == "switch" and switch_task == task then
      switch_task = nil
    elseif action == "connect" and connect_task == task then
      connect_task = nil
    end

    if exit_code == 0 then
      if action == "switch" then
        notify(cfg, "Dell KVM", result_text(std_out, std_err, "Monitor input switched."))
      end
      return
    end

    local title = action == "switch" and "Dell KVM switch failed" or "Dell KVM Bluetooth claim failed"
    notify(cfg, title, result_text(std_out, std_err, "Unknown error"))
  end, script_arguments(action, cfg))

  if not task then
    notify(cfg, "Dell KVM", "Unable to start the " .. action .. " task.")
    return
  end

  if action == "switch" then
    switch_task = task
  else
    connect_task = task
  end
  task:start()
end

local function schedule_connect(cfg)
  if connect_timer then
    connect_timer:stop()
    connect_timer = nil
  end

  connect_timer = hs.timer.doAfter(cfg.connectDelaySeconds or 1.5, function()
    connect_timer = nil
    if display_is_attached(cfg) then
      run_action("connect", cfg)
    end
  end)
end

function M.init(config)
  local cfg = config.dellKvm or {}
  if cfg.enabled == false then
    return
  end

  if not cfg.hotkey or not cfg.hotkey[1] or not cfg.hotkey[2] then
    notify(cfg, "Dell KVM", "No switch hotkey is configured.")
    return
  end

  hotkey = hs.hotkey.bind(cfg.hotkey[1], cfg.hotkey[2], function()
    run_action("switch", cfg)
  end)

  local was_attached = display_is_attached(cfg)
  screen_watcher = hs.screen.watcher.new(function()
    local attached = display_is_attached(cfg)
    if attached and not was_attached then
      schedule_connect(cfg)
    elseif not attached and connect_timer then
      connect_timer:stop()
      connect_timer = nil
    end
    was_attached = attached
  end)
  screen_watcher:start()

  if was_attached then
    schedule_connect(cfg)
  end
end

return M
