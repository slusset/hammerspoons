local M = {}

local timer = nil
local screen_watcher = nil
local battery_watcher = nil
local paused = false
local running = false

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
    clamshell_likely = has_external and not has_internal,
  }
end

local function poke(cfg)
  local mode = cfg.mode or "zen"

  if mode == "mouse" then
    local pos = hs.mouse.absolutePosition()
    hs.mouse.absolutePosition({ x = pos.x + 1, y = pos.y })
    hs.timer.usleep(20000)
    hs.mouse.absolutePosition(pos)
    return
  end

  -- "zen": post a zero-delta mouse move plus user activity, avoiding visible cursor movement.
  local pos = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pos):post()
  hs.caffeinate.declareUserActivity()
end

local function notify(enabled, paused_state)
  local state = enabled and "running" or "stopped"
  local suffix = paused_state and " (paused)" or ""
  hs.notify.new({
    title = "Hammerspoon",
    informativeText = "Jiggler " .. state .. suffix,
  }):send()
end

function M.init(config)
  local cfg = config.jiggler or {}
  if cfg.enabled == false then
    return
  end

  local function refresh(trigger)
    local display_state = get_display_state()
    local on_ac_power = (hs.battery.powerSource() or "") == "AC Power"

    local allowed = true
    if cfg.whenExternalDisplay ~= false then
      allowed = allowed and display_state.has_external
    end
    if cfg.requireClamshell then
      allowed = allowed and display_state.clamshell_likely
    end
    if cfg.requireACPower ~= false then
      allowed = allowed and on_ac_power
    end

    local should_run = allowed and not paused

    if should_run and not timer then
      local interval = cfg.intervalSeconds or 300
      timer = hs.timer.doEvery(interval, function()
        poke(cfg)
      end)
      if cfg.runImmediatelyOnEnable then
        poke(cfg)
      end
    elseif not should_run and timer then
      timer:stop()
      timer = nil
    end

    if running ~= should_run then
      running = should_run
      if cfg.showNotifications then
        notify(running, paused)
      end
    elseif cfg.showNotifications and trigger == "manual" then
      notify(running, paused)
    end
  end

  if cfg.toggleHotkey and cfg.toggleHotkey[1] and cfg.toggleHotkey[2] then
    hs.hotkey.bind(cfg.toggleHotkey[1], cfg.toggleHotkey[2], function()
      paused = not paused
      refresh("manual")
    end)
  end

  screen_watcher = hs.screen.watcher.new(refresh)
  battery_watcher = hs.battery.watcher.new(refresh)
  screen_watcher:start()
  battery_watcher:start()
  refresh()
end

return M
