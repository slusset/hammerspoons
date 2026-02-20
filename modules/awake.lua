local M = {}

local screen_watcher = nil
local battery_watcher = nil
local poll_timer = nil
local awake_enabled = nil
local manual_awake_override = false

local function is_builtin_screen(screen)
  local name = string.lower(screen:name() or "")
  return name:find("built%-in") ~= nil
    or name:find("color lcd") ~= nil
    or name:find("liquid retina") ~= nil
    or name:find("internal") ~= nil
end

local function get_display_state()
  local screens = hs.screen.allScreens()
  local has_external = false
  local has_internal = false

  for _, screen in ipairs(screens) do
    if is_builtin_screen(screen) then
      has_internal = true
    else
      has_external = true
    end
  end

  return {
    has_external = has_external,
    has_internal = has_internal,
    clamshell_likely = has_external and not has_internal,
  }
end

local function set_awake(enabled, prevent_display_sleep)
  local ok_sys = pcall(function()
    hs.caffeinate.set("systemIdle", enabled, true)
  end)
  local ok_display = pcall(function()
    local display_enabled = prevent_display_sleep and enabled or false
    hs.caffeinate.set("displayIdle", display_enabled, true)
  end)

  if not ok_sys or not ok_display then
    hs.alert.show("Awake toggle partially failed")
  end
end

function M.init(config)
  local cfg = config.awake or {}
  if cfg.enabled == false then
    return
  end

  local function refresh(trigger)
    local display_state = get_display_state()
    local on_ac_power = (hs.battery.powerSource() or "") == "AC Power"

    local should_enable_auto = true
    if cfg.whenExternalDisplay ~= false then
      should_enable_auto = should_enable_auto and display_state.has_external
    end
    if cfg.requireClamshell then
      should_enable_auto = should_enable_auto and display_state.clamshell_likely
    end
    if cfg.requireACPower ~= false then
      should_enable_auto = should_enable_auto and on_ac_power
    end

    local should_enable = manual_awake_override or should_enable_auto

    if should_enable ~= awake_enabled then
      set_awake(should_enable, cfg.preventDisplaySleep == true)
      awake_enabled = should_enable

      if cfg.showNotifications then
        local source = manual_awake_override and "manual" or "auto"
        local text = should_enable and ("Awake mode enabled (" .. source .. ")") or "Awake mode disabled"
        hs.notify.new({
          title = "Hammerspoon",
          informativeText = text,
        }):send()
      end
    elseif cfg.showNotifications and trigger == "manual" then
      local source = manual_awake_override and "manual" or "auto"
      local text = should_enable and ("Awake mode unchanged (" .. source .. ")") or "Awake mode unchanged"
      hs.notify.new({
        title = "Hammerspoon",
        informativeText = text,
      }):send()
    end
  end

  if cfg.manualToggleHotkey and cfg.manualToggleHotkey[1] and cfg.manualToggleHotkey[2] then
    hs.hotkey.bind(cfg.manualToggleHotkey[1], cfg.manualToggleHotkey[2], function()
      manual_awake_override = not manual_awake_override
      refresh("manual")
    end)
  end

  screen_watcher = hs.screen.watcher.new(refresh)
  battery_watcher = hs.battery.watcher.new(refresh)
  poll_timer = hs.timer.doEvery(cfg.pollSeconds or 20, refresh)

  screen_watcher:start()
  battery_watcher:start()
  refresh()
end

return M
