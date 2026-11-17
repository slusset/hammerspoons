return {
  logLevel = "info",
  notifications = {
    enabled = true,
  },
  ipc = {
    enabled = true,
    autoInstallCLI = false,
  },
  outlookAX = {
    enabled = true,
    defaultDepth = 6,
    defaultMaxNodes = 700,
  },
  reload = {
    watchConfigDir = true,
    hotkey = { { "cmd", "alt", "ctrl" }, "R" },
  },
  windowTiling = {
    enabled = true,
    screenMargin = 8,
    windowMargin = 8,
    centerSize = { w = 0.48, h = 0.82 },
    hotkeys = {
      left = { { "ctrl", "alt" }, "Left" },
      right = { { "ctrl", "alt" }, "Right" },
      bottomLeft = { { "ctrl", "alt", "cmd" }, "Down" },
      bottomRight = { { "ctrl", "alt", "cmd" }, "Up" },
      maximize = { { "ctrl", "alt" }, "Return" },
      center = { { "ctrl", "alt" }, "C" },
      nextScreen = { { "ctrl", "alt" }, "N" },
      previousScreen = { { "ctrl", "alt" }, "P" },
    },
  },
  keystrokes = {
    enabled = true,
    notifyOnShellFinish = false,
    hotkeys = {
      {
        mods = { "ctrl", "alt", "cmd" },
        key = "I",
        description = "Open iTerm",
        action = { type = "app", name = "iTerm" },
      },
      {
        mods = { "ctrl", "alt", "cmd" },
        key = "L",
        description = "Lock screen",
        action = { type = "hs", command = "lockScreen" },
      },
    },
  },
  dellKvm = {
    enabled = false,
    displayNumber = 1,
    inputs = { 15, 25 },
    keyfobVolumeUUID = "",
    m1ddcBinary = "/opt/homebrew/bin/m1ddc",
    hotkey = { { "ctrl", "shift" }, "1" },
    showNotifications = true,
  },
}
