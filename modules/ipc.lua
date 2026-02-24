local M = {}

function M.init(config)
  local cfg = config.ipc or {}
  if cfg.enabled == false then
    return
  end

  local ok, ipc = pcall(require, "hs.ipc")
  if not ok or not ipc then
    hs.printf("[ipc] hs.ipc is unavailable; hs CLI commands are disabled")
    return
  end

  if cfg.autoInstallCLI == true then
    local ok_install, err = pcall(function()
      ipc.cliInstall()
    end)
    if not ok_install then
      hs.printf("[ipc] cliInstall failed: %s", tostring(err))
    end
  end
end

return M
