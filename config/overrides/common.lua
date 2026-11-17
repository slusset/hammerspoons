return {
  dellKvm = {
    enabled = true,
    keyfobVolumeUUID = "5CCAA7C9-F028-3C33-83BF-D05BB4BAC9C0",
  },
  windowTiling = {
    -- Match Rectangle export defaults.
    screenMargin = 0,
    windowMargin = 8,
    resizeStepPixels = 30,
    hotkeys = {
      left = { { "cmd", "alt" }, "Left" },
      right = { { "cmd", "alt" }, "Right" },
      bottomLeft = { { "cmd", "ctrl", "shift" }, "Left" },
      bottomRight = { { "cmd", "ctrl", "shift" }, "Right" },
      center = { { "cmd", "alt" }, "C" },
      maximize = { { "cmd", "alt" }, "F" },
      maximizeHeight = { { "ctrl", "alt", "shift" }, "Up" },
      larger = { { "ctrl", "alt", "shift" }, "Right" },
      smaller = { { "ctrl", "alt", "shift" }, "Left" },
      nextScreen = { { "cmd", "ctrl", "alt" }, "Right" },
      previousScreen = { { "cmd", "ctrl", "alt" }, "Left" },
      restore = { { "ctrl", "alt" }, "delete" },
    },
  },
}
