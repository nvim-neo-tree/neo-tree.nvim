local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local M = {}

---Either rm-like, or a custom list of commands
---@alias neotree.trash.Command string[]|fun(paths: string[]):string[][]?

---Returns a list of possible commands for a platform.
---@param paths string[]
---@return (neotree.trash.Command)[] possible_commands
M.generate_commands = function(paths)
  log.assert(#paths > 0)
  local commands = {
    require("neo-tree").config.trash.cmd,
  }

  -- Using code from https://github.com/folke/snacks.nvim/blob/ed08ef1a630508ebab098aa6e8814b89084f8c03/lua/snacks/explorer/actions.lua
  if utils.is_macos then
    vim.list_extend(commands, {
      { "trash" }, -- trash-cli (Python or Node.js)
      function(p)
        local cmds = {}
        for i, path in ipairs(p) do
          cmds[i] = {
            "osascript",
            "-e",
            ('tell application "Finder" to delete POSIX file "%s"'):format(
              path:gsub("\\", "\\\\"):gsub('"', '\\"')
            ),
          }
        end
        return cmds
      end,
    })
  elseif utils.is_windows then
    vim.list_extend(commands, {
      { "trash" }, -- trash-cli (Python or Node.js)
      function(p)
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
          "Add-Type -AssemblyName Microsoft.VisualBasic;",
        }
        for _, path in ipairs(p) do
          local escaped = path:gsub("\\", "\\\\"):gsub("'", "''")
          pwsh_cmds[#pwsh_cmds + 1] = ("[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('%s','OnlyErrorDialogs', 'SendToRecycleBin');"):format(
            escaped
          )
        end
        cmd[#cmd + 1] = table.concat(pwsh_cmds, " ")
        return {
          cmd,
        }
      end,
    })
  else
    vim.list_extend(commands, {
      { "gio", "trash" }, -- Most universally available on modern Linux
      { "trash" }, -- trash-cli (Python or Node.js)
      function(p)
        local kioclient = utils.executable("kioclient5") or utils.executable("kioclient")
        if not kioclient then
          return nil
        end
        local kioclient_cmds = {}
        for _, path in ipairs(p) do
          kioclient_cmds[#kioclient_cmds + 1] = { kioclient, "move", path, "trash:/" }
        end
        return kioclient_cmds
      end,
    })
  end
  return commands
end

---@param paths string[]
---@return boolean success
---@return string? err
M.trash = function(paths)
  local cmds = M.generate_commands(paths)
  for _, command in ipairs(cmds) do
    repeat
      if type(command) == "table" then
        if not utils.executable(command[1]) then
          log.debug("Trash command", command, "not executable")
          break -- try next command
        end

        local full_command = vim.list_extend({
          unpack(command),
        }, paths)
        log.debug("Running trash command", full_command)
        local trash_ok, output = utils.execute_command(full_command)
        if not trash_ok then
          return false, "Could not trash with " .. full_command .. ":" .. output
        end
        log.debug("Trashed", paths, "using", full_command)
        return true
      end

      if type(command) == "function" then
        local commands = command(paths)
        if not commands then
          break -- try next command
        end

        for _, cmd in ipairs(commands) do
          -- assume it's already executable
          local trash_ok = utils.execute_command(cmd)
          if not trash_ok then
            return false,
              "Error executing trash command " .. table.concat(cmd, " ") .. ", aborting operation."
          end
        end
        return true
      end

      return false, "Invalid trash command:" .. command
    until true
  end
  return false
end

return M
