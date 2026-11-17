local M = {}

local switch_task = nil

local function notify(cfg, title, text)
  if cfg.showNotifications == false then
    return
  end

  hs.notify.new({
    title = title,
    informativeText = text,
  }):send()
end

local function script_arguments(cfg)
  local inputs = cfg.inputs or {}
  return {
    hs.configdir .. "/scripts/switch-dell-monitor.sh",
    "switch",
    "--display", tostring(cfg.displayNumber or 1),
    "--input-a", tostring(inputs[1] or 15),
    "--input-b", tostring(inputs[2] or 25),
    "--keyfob-volume-uuid", cfg.keyfobVolumeUUID or "",
    "--m1ddc", cfg.m1ddcBinary or "/opt/homebrew/bin/m1ddc",
  }
end

local function result_text(std_out, std_err, fallback)
  local err = (std_err or ""):match("^%s*(.-)%s*$")
  if err ~= "" then
    return err
  end
  local out = (std_out or ""):match("^%s*(.-)%s*$")
  if out ~= "" then
    return out
  end
  return fallback
end

local function switch_input(cfg)
  if switch_task and switch_task:isRunning() then
    notify(cfg, "Dell KVM", "A monitor switch is already running.")
    return
  end

  print("Dell KVM hotkey fired")
  local args = script_arguments(cfg)
  local task = hs.task.new("/bin/bash", function(exit_code, std_out, std_err)
    switch_task = nil
    print("Dell KVM exit", exit_code, "stdout", std_out, "stderr", std_err)

    if exit_code == 0 then
      notify(cfg, "Dell KVM", result_text(std_out, std_err, "Monitor input switched."))
    else
      notify(cfg, "Dell KVM switch failed", result_text(std_out, std_err, "Unknown error"))
    end
  end, args)

  if not task or not task:start() then
    local message = "Unable to start " .. args[1]
    print("Dell KVM", message)
    notify(cfg, "Dell KVM switch failed", message)
    return
  end
  switch_task = task
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

  hs.hotkey.bind(cfg.hotkey[1], cfg.hotkey[2], function()
    switch_input(cfg)
  end)
end

return M
