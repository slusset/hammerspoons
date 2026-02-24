local M = {}

local function safe_attr(element, name)
  local ok, value = pcall(function()
    return element:attributeValue(name)
  end)
  if not ok then
    return nil
  end
  return value
end

local function sanitize(value, max_len)
  if value == nil then
    return "-"
  end

  local raw = tostring(value):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then
    return "-"
  end

  local limit = max_len or 80
  if #raw > limit then
    return raw:sub(1, limit - 3) .. "..."
  end
  return raw
end

local function role_sort_keys(map)
  local keys = {}
  for key, _ in pairs(map) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local function get_outlook_window_ax()
  local app = hs.application.get("Microsoft Outlook")
  if not app then
    return nil, nil, "Microsoft Outlook is not running."
  end

  local win = app:focusedWindow() or app:mainWindow()
  if not win then
    return nil, nil, "No Outlook window is available."
  end

  local ax_window = hs.axuielement.windowElement(win)
  if not ax_window then
    return nil, nil, "Unable to obtain AX window element."
  end

  return ax_window, win, nil
end

local function get_focused_element()
  local ok, system = pcall(function()
    return hs.axuielement.systemWideElement()
  end)
  if not ok or not system then
    return nil
  end

  local ok_focused, focused = pcall(function()
    return system:attributeValue("AXFocusedUIElement")
  end)
  if not ok_focused then
    return nil
  end
  return focused
end

local function is_editable_candidate(role, editable)
  if editable == true then
    return true
  end

  return role == "AXTextField"
    or role == "AXTextArea"
    or role == "AXComboBox"
    or role == "AXSearchField"
end

local function walk(element, depth, path, state)
  if state.node_count >= state.max_nodes then
    state.truncated = true
    return
  end

  state.node_count = state.node_count + 1

  local role = sanitize(safe_attr(element, "AXRole"), 40)
  local subrole = sanitize(safe_attr(element, "AXSubrole"), 40)
  local title = sanitize(safe_attr(element, "AXTitle"), 90)
  local description = sanitize(safe_attr(element, "AXDescription"), 90)
  local identifier = sanitize(safe_attr(element, "AXIdentifier"), 90)
  local value = sanitize(safe_attr(element, "AXValue"), 90)
  local editable = safe_attr(element, "AXEditable") == true

  if state.focused_element ~= nil and element == state.focused_element then
    state.focused_path = path
    state.focused = {
      role = role,
      subrole = subrole,
      title = title,
      description = description,
      identifier = identifier,
      editable = editable,
      value = value,
    }
  end

  state.role_counts[role] = (state.role_counts[role] or 0) + 1

  local indent = string.rep("  ", depth)
  table.insert(
    state.lines,
    string.format(
      "%s%s role=%s subrole=%s title=%s desc=%s id=%s editable=%s value=%s",
      indent,
      path,
      role,
      subrole,
      title,
      description,
      identifier,
      editable and "true" or "false",
      value
    )
  )

  if is_editable_candidate(role, editable) then
    table.insert(state.editables, {
      path = path,
      role = role,
      subrole = subrole,
      title = title,
      description = description,
      identifier = identifier,
      value = value,
      editable = editable,
    })
  end

  if depth >= state.max_depth then
    return
  end

  local children = safe_attr(element, "AXChildren")
  if type(children) ~= "table" then
    return
  end

  for i, child in ipairs(children) do
    if state.node_count >= state.max_nodes then
      state.truncated = true
      return
    end
    walk(child, depth + 1, string.format("%s.%d", path, i), state)
  end
end

local function inspect_window(max_depth, max_nodes)
  local ax_window, win, err = get_outlook_window_ax()
  if err then
    return nil, err
  end

  local state = {
    lines = {},
    editables = {},
    role_counts = {},
    node_count = 0,
    truncated = false,
    max_depth = max_depth,
    max_nodes = max_nodes,
    focused_element = get_focused_element(),
    focused_path = nil,
    focused = nil,
  }

  walk(ax_window, 0, "0", state)

  return {
    state = state,
    window_title = win:title() or "(untitled)",
  }, nil
end

local function sleep_seconds(seconds)
  local value = tonumber(seconds) or 0
  if value <= 0 then
    return
  end
  hs.timer.usleep(math.floor(value * 1000000))
end

local function activate_outlook()
  local app = hs.application.get("Microsoft Outlook")
  if not app then
    hs.application.launchOrFocus("Microsoft Outlook")
    sleep_seconds(0.35)
    app = hs.application.get("Microsoft Outlook")
  end

  if not app then
    return nil, "Microsoft Outlook is not running."
  end

  app:activate(true)
  return app, nil
end

local function find_first_descendant(element, max_depth, predicate, depth)
  if not element then
    return nil
  end

  local current_depth = depth or 0
  if predicate(element) then
    return element
  end

  if current_depth >= max_depth then
    return nil
  end

  local children = safe_attr(element, "AXChildren")
  if type(children) ~= "table" then
    return nil
  end

  for _, child in ipairs(children) do
    local found = find_first_descendant(child, max_depth, predicate, current_depth + 1)
    if found then
      return found
    end
  end

  return nil
end

local function focus_element(element)
  if not element then
    return false
  end

  local ok_set, set_result = pcall(function()
    return element:setAttributeValue("AXFocused", true)
  end)
  if ok_set and (set_result == nil or set_result == true) then
    return true
  end

  local ok_press, press_result = pcall(function()
    return element:performAction("AXPress")
  end)
  if ok_press and (press_result == nil or press_result == true) then
    return true
  end

  return false
end

local function paste_text(text)
  if not text or text == "" then
    return
  end
  hs.pasteboard.setContents(text)
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)
end

local function find_by_identifier(ax_window, identifier, max_depth)
  return find_first_descendant(ax_window, max_depth, function(node)
    return safe_attr(node, "AXIdentifier") == identifier
  end)
end

local function find_first_by_role(ax_window, role, max_depth)
  return find_first_descendant(ax_window, max_depth, function(node)
    return safe_attr(node, "AXRole") == role
  end)
end

local function find_send_button(ax_window, max_depth)
  return find_first_descendant(ax_window, max_depth, function(node)
    if safe_attr(node, "AXRole") ~= "AXButton" then
      return false
    end
    local description = safe_attr(node, "AXDescription")
    local title = safe_attr(node, "AXTitle")
    return description == "Send" or title == "Send"
  end)
end

local function focused_matches(target_role, target_identifier)
  local focused = get_focused_element()
  if not focused then
    return false
  end

  if target_role and safe_attr(focused, "AXRole") ~= target_role then
    return false
  end

  if target_identifier and safe_attr(focused, "AXIdentifier") ~= target_identifier then
    return false
  end

  return true
end

local function focus_or_tab_to(target_element, target_role, target_identifier, step_wait, max_tabs)
  if target_element and focus_element(target_element) then
    sleep_seconds(step_wait)
    if focused_matches(target_role, target_identifier) then
      return true
    end
  end

  local tab_count = max_tabs or 0
  for _ = 1, tab_count do
    hs.eventtap.keyStroke({}, "tab", 0)
    sleep_seconds(step_wait)
    if focused_matches(target_role, target_identifier) then
      return true
    end
  end

  return false
end

local function build_summary(result, only_counts)
  local state = result.state
  local out = {}

  table.insert(out, string.format("Outlook window title: %s", sanitize(result.window_title, 140)))
  table.insert(out, string.format("Scanned nodes: %d (depth=%d, maxNodes=%d)", state.node_count, state.max_depth, state.max_nodes))
  if state.truncated then
    table.insert(out, "Scan truncated because max node limit was hit.")
  end

  if state.focused then
    table.insert(
      out,
      string.format(
        "Focused element: path=%s role=%s subrole=%s title=%s desc=%s id=%s editable=%s value=%s",
        sanitize(state.focused_path, 40),
        state.focused.role,
        state.focused.subrole,
        state.focused.title,
        state.focused.description,
        state.focused.identifier,
        state.focused.editable and "true" or "false",
        state.focused.value
      )
    )
  else
    table.insert(out, "Focused element: not found within scanned window tree.")
  end

  table.insert(out, "Role counts:")
  for _, role in ipairs(role_sort_keys(state.role_counts)) do
    table.insert(out, string.format("  %s: %d", role, state.role_counts[role]))
  end

  table.insert(out, string.format("Editable candidates: %d", #state.editables))
  for i, item in ipairs(state.editables) do
    table.insert(
      out,
      string.format(
        "  [%d] path=%s role=%s subrole=%s title=%s desc=%s id=%s editable=%s value=%s",
        i,
        item.path,
        item.role,
        item.subrole,
        item.title,
        item.description,
        item.identifier,
        item.editable and "true" or "false",
        item.value
      )
    )
  end

  if only_counts then
    return table.concat(out, "\n")
  end

  table.insert(out, "AX tree:")
  for _, line in ipairs(state.lines) do
    table.insert(out, "  " .. line)
  end

  return table.concat(out, "\n")
end

local function to_number_or_default(value, default)
  local num = tonumber(value)
  if not num then
    return default
  end
  return math.floor(num)
end

function M.dump_compose(max_depth, max_nodes)
  local cfg = M.config or {}
  local depth = to_number_or_default(max_depth, cfg.defaultDepth or 6)
  local nodes = to_number_or_default(max_nodes, cfg.defaultMaxNodes or 700)

  local result, err = inspect_window(depth, nodes)
  if err then
    print(err)
    return err
  end

  local text = build_summary(result, false)
  print(text)
  return text
end

function M.field_counts(max_depth, max_nodes)
  local cfg = M.config or {}
  local depth = to_number_or_default(max_depth, cfg.defaultDepth or 6)
  local nodes = to_number_or_default(max_nodes, cfg.defaultMaxNodes or 700)

  local result, err = inspect_window(depth, nodes)
  if err then
    print(err)
    return err
  end

  local text = build_summary(result, true)
  print(text)
  return text
end

function M.focused()
  local focused = get_focused_element()
  if not focused then
    local text = "No focused accessibility element."
    print(text)
    return text
  end

  local role = sanitize(safe_attr(focused, "AXRole"), 40)
  local subrole = sanitize(safe_attr(focused, "AXSubrole"), 40)
  local title = sanitize(safe_attr(focused, "AXTitle"), 120)
  local description = sanitize(safe_attr(focused, "AXDescription"), 120)
  local identifier = sanitize(safe_attr(focused, "AXIdentifier"), 120)
  local value = sanitize(safe_attr(focused, "AXValue"), 120)
  local editable = safe_attr(focused, "AXEditable") == true
  local focused_window = safe_attr(focused, "AXWindow")
  local win_title = "-"

  if focused_window then
    win_title = sanitize(safe_attr(focused_window, "AXTitle"), 140)
  end

  local text = string.format(
    "Focused role=%s subrole=%s title=%s desc=%s id=%s editable=%s value=%s window=%s",
    role,
    subrole,
    title,
    description,
    identifier,
    editable and "true" or "false",
    value,
    win_title
  )
  print(text)
  return text
end

function M.send_current(send_mode)
  local mode = tostring(send_mode or "keystroke")
  local _, activate_err = activate_outlook()
  if activate_err then
    print(activate_err)
    return activate_err
  end
  sleep_seconds(0.1)

  if mode == "button" then
    local ax_window, _, err = get_outlook_window_ax()
    if err then
      print(err)
      return err
    end

    local send_button = find_send_button(ax_window, 12)
    if not send_button then
      local missing = "Unable to locate Send button in current Outlook window."
      print(missing)
      return missing
    end

    local ok_press = pcall(function()
      send_button:performAction("AXPress")
    end)
    if not ok_press then
      local press_err = "Failed to press Send button via AX."
      print(press_err)
      return press_err
    end

    local text = "Send triggered via AX button press."
    print(text)
    return text
  end

  hs.eventtap.keyStroke({ "cmd" }, "return", 0)
  local text = "Send triggered via Cmd+Return."
  print(text)
  return text
end

function M.compose(options)
  local opts = type(options) == "table" and options or {}
  local to_value = tostring(opts.to or "")
  local subject_value = tostring(opts.subject or "")
  local body_value = tostring(opts.body or "")
  local send_now = opts.sendNow == true or opts.send_now == true
  local send_mode = tostring(opts.sendMode or opts.send_mode or "keystroke")
  local focus_wait = tonumber(opts.focusWait or opts.focus_wait or 0.2) or 0.2
  local compose_wait = tonumber(opts.composeWait or opts.compose_wait or 0.9) or 0.9
  local step_wait = tonumber(opts.stepWait or opts.step_wait or 0.12) or 0.12

  if to_value == "" then
    local err = "compose requires a non-empty 'to' value."
    print(err)
    return err
  end

  local _, activate_err = activate_outlook()
  if activate_err then
    print(activate_err)
    return activate_err
  end
  sleep_seconds(focus_wait)

  hs.eventtap.keyStroke({ "cmd" }, "n", 0)
  sleep_seconds(compose_wait)

  local ax_window, _, err = get_outlook_window_ax()
  if err then
    print(err)
    return err
  end

  local max_depth = 14
  local to_field = find_by_identifier(ax_window, "toTextField", max_depth)
  local subject_field = find_by_identifier(ax_window, "subjectTextField", max_depth)
  local body_field = find_first_by_role(ax_window, "AXTextArea", max_depth)

  if not to_field then
    local missing_to = "Unable to locate To field (AXIdentifier=toTextField)."
    print(missing_to)
    return missing_to
  end

  if not focus_or_tab_to(to_field, "AXTextField", "toTextField", step_wait, 2) then
    local focus_to_err = "Unable to focus To field via AX."
    print(focus_to_err)
    return focus_to_err
  end
  paste_text(to_value)
  sleep_seconds(step_wait)

  if subject_value ~= "" then
    if not subject_field then
      local missing_subject = "Unable to locate Subject field (AXIdentifier=subjectTextField)."
      print(missing_subject)
      return missing_subject
    end
    if not focus_or_tab_to(subject_field, "AXTextField", "subjectTextField", step_wait, 3) then
      local focus_subject_err = "Unable to focus Subject field via AX."
      print(focus_subject_err)
      return focus_subject_err
    end
    paste_text(subject_value)
    sleep_seconds(step_wait)
  end

  if body_value ~= "" then
    if not body_field then
      local missing_body = "Unable to locate body editor (AXTextArea)."
      print(missing_body)
      return missing_body
    end
    if not focus_or_tab_to(body_field, "AXTextArea", nil, step_wait, 3) then
      local focus_body_err = "Unable to focus body editor via AX."
      print(focus_body_err)
      return focus_body_err
    end
    paste_text(body_value)
    sleep_seconds(step_wait)
  end

  if send_now then
    return M.send_current(send_mode)
  end

  local text = string.format(
    "Compose created via AX identifiers (to=%s, subject=%s, body=%s).",
    to_value ~= "" and "yes" or "no",
    subject_value ~= "" and "yes" or "no",
    body_value ~= "" and "yes" or "no"
  )
  print(text)
  return text
end

function M.init(config)
  local cfg = config.outlookAX or {}
  if cfg.enabled == false then
    return
  end

  M.config = cfg

  _G.OutlookAX = _G.OutlookAX or {}
  _G.OutlookAX.dumpCompose = function(max_depth, max_nodes)
    return M.dump_compose(max_depth, max_nodes)
  end
  _G.OutlookAX.fieldCounts = function(max_depth, max_nodes)
    return M.field_counts(max_depth, max_nodes)
  end
  _G.OutlookAX.focused = function()
    return M.focused()
  end
  _G.OutlookAX.sendCurrent = function(send_mode)
    return M.send_current(send_mode)
  end
  _G.OutlookAX.compose = function(options)
    return M.compose(options)
  end
end

return M
