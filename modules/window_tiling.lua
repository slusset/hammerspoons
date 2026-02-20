local M = {}
local previous_frames_by_window_id = {}

local function focused_window_or_nil()
  local win = hs.window.focusedWindow()
  if not win then
    hs.alert.show("No focused window")
  end
  return win
end

local function apply_unit(win, unit, screen_margin, window_margin)
  local screen = win:screen()
  local sf = screen:frame()

  local inner = {
    x = sf.x + screen_margin,
    y = sf.y + screen_margin,
    w = sf.w - (screen_margin * 2),
    h = sf.h - (screen_margin * 2),
  }

  local frame = {
    x = inner.x + (inner.w * unit.x) + (window_margin / 2),
    y = inner.y + (inner.h * unit.y) + (window_margin / 2),
    w = (inner.w * unit.w) - window_margin,
    h = (inner.h * unit.h) - window_margin,
  }

  win:setFrame(frame)
end

local function save_frame(win)
  local id = win:id()
  if id then
    previous_frames_by_window_id[id] = win:frame()
  end
end

local function restore_saved_frame(win)
  local id = win:id()
  if not id then
    return false
  end
  local frame = previous_frames_by_window_id[id]
  if not frame then
    return false
  end
  win:setFrame(frame)
  return true
end

local function scale_window(win, step_pct, step_pixels, screen_margin, window_margin)
  local sf = win:screen():frame()
  local inner = {
    x = sf.x + screen_margin,
    y = sf.y + screen_margin,
    w = sf.w - (screen_margin * 2),
    h = sf.h - (screen_margin * 2),
  }

  local current = win:frame()
  local min_x = inner.x + (window_margin / 2)
  local min_y = inner.y + (window_margin / 2)
  local max_w = inner.w - window_margin
  local max_h = inner.h - window_margin
  local delta_w = step_pixels or (inner.w * step_pct)
  local delta_h = step_pixels or (inner.h * step_pct)

  local new_w = math.max(120, math.min(max_w, current.w + delta_w))
  local new_h = math.max(120, math.min(max_h, current.h + delta_h))
  local new_x = current.x - ((new_w - current.w) / 2)
  local new_y = current.y - ((new_h - current.h) / 2)

  if new_x < min_x then new_x = min_x end
  if new_y < min_y then new_y = min_y end
  if new_x + new_w > min_x + max_w then new_x = (min_x + max_w) - new_w end
  if new_y + new_h > min_y + max_h then new_y = (min_y + max_h) - new_h end

  win:setFrame({
    x = new_x,
    y = new_y,
    w = new_w,
    h = new_h,
  })
end

local function with_saved_frame(action)
  return function()
    local win = focused_window_or_nil()
    if not win then
      return
    end
    save_frame(win)
    action(win)
  end
end

function M.init(config)
  local cfg = config.windowTiling or {}
  if cfg.enabled == false then
    return
  end

  local screen_margin = cfg.screenMargin or 8
  local window_margin = cfg.windowMargin or 8
  local center_size = cfg.centerSize or { w = 0.64, h = 0.82 }
  local resize_step = cfg.resizeStep or 0.05
  local resize_step_pixels = cfg.resizeStepPixels

  local actions = {
    left = with_saved_frame(function(win)
      apply_unit(win, { x = 0.0, y = 0.0, w = 0.5, h = 1.0 }, screen_margin, window_margin)
    end),
    right = with_saved_frame(function(win)
      apply_unit(win, { x = 0.5, y = 0.0, w = 0.5, h = 1.0 }, screen_margin, window_margin)
    end),
    top = with_saved_frame(function(win)
      apply_unit(win, { x = 0.0, y = 0.0, w = 1.0, h = 0.5 }, screen_margin, window_margin)
    end),
    bottom = with_saved_frame(function(win)
      apply_unit(win, { x = 0.0, y = 0.5, w = 1.0, h = 0.5 }, screen_margin, window_margin)
    end),
    topLeft = with_saved_frame(function(win)
      apply_unit(win, { x = 0.0, y = 0.0, w = 0.5, h = 0.5 }, screen_margin, window_margin)
    end),
    topRight = with_saved_frame(function(win)
      apply_unit(win, { x = 0.5, y = 0.0, w = 0.5, h = 0.5 }, screen_margin, window_margin)
    end),
    bottomLeft = with_saved_frame(function(win)
      apply_unit(win, { x = 0.0, y = 0.5, w = 0.5, h = 0.5 }, screen_margin, window_margin)
    end),
    bottomRight = with_saved_frame(function(win)
      apply_unit(win, { x = 0.5, y = 0.5, w = 0.5, h = 0.5 }, screen_margin, window_margin)
    end),
    maximize = with_saved_frame(function(win)
      apply_unit(win, { x = 0.0, y = 0.0, w = 1.0, h = 1.0 }, screen_margin, window_margin)
    end),
    center = with_saved_frame(function(win)
      local x = (1.0 - center_size.w) / 2.0
      local y = (1.0 - center_size.h) / 2.0
      apply_unit(win, { x = x, y = y, w = center_size.w, h = center_size.h }, screen_margin, window_margin)
    end),
    maximizeHeight = with_saved_frame(function(win)
      local frame = win:frame()
      local sf = win:screen():frame()
      frame.y = sf.y + screen_margin + (window_margin / 2)
      frame.h = sf.h - (screen_margin * 2) - window_margin
      win:setFrame(frame)
    end),
    larger = with_saved_frame(function(win)
      scale_window(win, resize_step, resize_step_pixels, screen_margin, window_margin)
    end),
    smaller = with_saved_frame(function(win)
      scale_window(win, -resize_step, resize_step_pixels and -resize_step_pixels or nil, screen_margin, window_margin)
    end),
    nextScreen = with_saved_frame(function(win)
      win:moveToScreen(win:screen():next())
    end),
    previousScreen = with_saved_frame(function(win)
      win:moveToScreen(win:screen():previous())
    end),
    restore = function()
      local win = focused_window_or_nil()
      if not win then return end
      if not restore_saved_frame(win) then
        hs.alert.show("No saved frame")
      end
    end,
  }

  for action_name, binding in pairs(cfg.hotkeys or {}) do
    local action = actions[action_name]
    if action and type(binding) == "table" and binding[1] and binding[2] then
      hs.hotkey.bind(binding[1], binding[2], action)
    end
  end
end

return M
