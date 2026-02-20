local M = {}

local function notify(title, text)
  hs.notify.new({
    title = title,
    informativeText = text,
  }):send()
end

function M.run_shell(command, notify_on_finish)
  local task = hs.task.new("/bin/zsh", function(exit_code, std_out, std_err)
    if not notify_on_finish then
      return
    end

    if exit_code == 0 then
      notify("Shell action complete", (std_out and #std_out > 0) and std_out or "Success")
    else
      local err = std_err or std_out or "Unknown error"
      notify("Shell action failed", err)
    end
  end, { "-lc", command })

  if not task then
    notify("Shell action failed", "Unable to start shell task")
    return
  end

  task:start()
end

return M

