local utils = require("neo-tree.utils")
local M = {}
M.generate_recycle_commands = function(paths)
  local powershell = utils.executable("pwsh") or utils.executable("powershell")
  if not powershell then
    return nil
  end

  local cmd = {
    powershell,
    "-NoProfile",
    "-Command",
  }

  local pwsh_cmds = {
    "$shell = New-Object -ComObject 'Shell.Application';",
    "$folder = $shell.NameSpace(0);",
  }
  for _, path in ipairs(paths) do
    local escaped = path:gsub("\\", "\\\\"):gsub("'", "''")
    pwsh_cmds[#pwsh_cmds + 1] = ([[$path = Get-Item '%s'; $folder.ParseName($path.FullName).InvokeVerb('delete');]]):format(
      escaped
    )
  end
  cmd[#cmd + 1] = table.concat(pwsh_cmds, " ")
  return {
    cmd,
  }
end

---@type neotree.trash.RestoreCommandGenerator
M.generate_restore_commands = function(paths)
  local powershell = utils.executable("pwsh") or utils.executable("powershell")
  if not powershell then
    return nil
  end

  local cmd = {
    powershell,
    "-NoProfile",
    "-Command",
  }

  local pwsh_cmds = {
    "$shell = New-Object -ComObject 'Shell.Application';",
    "$bin = $shell.NameSpace(0xA);",
    "$items = $bin.Items();",
  }

  for _, path in ipairs(paths) do
    -- Escape backslashes and single quotes
    local escaped = path:gsub("\\", "\\\\"):gsub("'", "''")

    -- Logic:
    -- 1. We look at the .Path property of the items in the Recycle Bin
    -- 2. If it matches the $R... path provided, we restore it
    local restore_logic = ([[$items | Where-Object { $_.Path -eq '%s' } | ForEach-Object { $_.InvokeVerb('undelete') };]]):format(
      escaped
    )
    pwsh_cmds[#pwsh_cmds + 1] = restore_logic
  end

  cmd[#cmd + 1] = table.concat(pwsh_cmds, " ")
  return {
    cmd,
  }
end
return M
