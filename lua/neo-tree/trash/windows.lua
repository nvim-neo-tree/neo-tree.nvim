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

  --- Assemble a .NET hashset with the items
  local pwsh_cmds = {
    "$paths = New-Object System.Collections.Generic.HashSet[string]();",
  }

  for _, path in ipairs(paths) do
    local escaped = path:gsub("'", "''")
    pwsh_cmds[#pwsh_cmds + 1] = ([[$null = $paths.Add('%s');]]):format(escaped)
  end

  local restore_logic = {
    "$shell = New-Object -ComObject 'Shell.Application';",
    "$bin = $shell.NameSpace(0xA);",
    "$bin.Items() | ForEach-Object {",
    "  if ($paths.Contains($_.Path)) {",
    "    try {",
    "      $_.InvokeVerb('undelete')",
    "    } catch {",
    '      [Console]::Error.WriteLine("Failed to restore $($_.Path): $($_.Exception.Message)")',
    "    }",
    "  }",
    "};",
  }

  for _, v in ipairs(restore_logic) do
    table.insert(pwsh_cmds, v)
  end

  cmd[#cmd + 1] = table.concat(pwsh_cmds, " ")

  return {
    cmd,
  }
end

return M
