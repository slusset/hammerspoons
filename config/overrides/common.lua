return {
  dellKvm = {
    enabled = true,
    keyfobVolumeUUID = "5CCAA7C9-F028-3C33-83BF-D05BB4BAC9C0",
    bluetoothDevices = {
      { name = "Magic Trackpad", address = "D0-C0-50-D3-45-F1" },
      { name = "Ted Slusser's Mouse", address = "30-D9-D9-8B-D8-CF" },
    },
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
  awake = {
    -- KVM switching can temporarily hide the external display; gate by AC +
    -- clamshell instead of current external-display visibility.
    whenExternalDisplay = false,
    requireClamshell = true,
    requireACPower = true,
    preventDisplaySleep = false,
    manualToggleHotkey = { { "ctrl", "alt", "cmd" }, "A" },
  },
  jiggler = {
    enabled = true,
    intervalSeconds = 300,
    mode = "zen",
    whenExternalDisplay = false,
    requireClamshell = true,
    requireACPower = true,
    toggleHotkey = { { "ctrl", "alt", "cmd" }, "J" },
  },
}
