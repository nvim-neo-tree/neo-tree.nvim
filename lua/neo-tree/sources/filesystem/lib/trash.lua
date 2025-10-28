local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local validate = require("neo-tree.health.typecheck").validate
local M = {}

---@alias neotree.trash.Command neotree.trash.PureCommand|neotree.trash.FunctionGenerator|neotree.trash.CommandGenerator

---@class neotree.trash.PureCommand
---@field healthcheck? fun(paths: string[]):boolean,string?
---@field [integer] string

---A function that may return commands to execute, in order.
---@alias neotree.trash.CommandGenerator fun(paths: string[]):neotree.trash.PureCommand[]?

---A function that may return a function that will do the trashing.
---@alias neotree.trash.FunctionGenerator fun(paths: string[]):((fun():success: boolean, err: string?)?)

-- Using programs mentioned by
-- https://github.com/folke/snacks.nvim/blob/ed08ef1a630508ebab098aa6e8814b89084f8c03/lua/snacks/explorer/actions.lua
local builtins = {
  macos = {
    { "trash" }, -- trash-cli, usually
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
  },
  linux = {
    {
      "gio",
      "trash",
      healthcheck = function()
        return utils.executable("gio") and utils.execute_command({ "gio", "trash", "--list" })
      end,
    },
    { "trash" }, -- trash-cli, usually
    function(p)
      local kioclient = utils.executable("kioclient") or utils.executable("kioclient5")
      if not kioclient then
        return nil
      end
      local kioclient_cmds = {}
      for _, path in ipairs(p) do
        kioclient_cmds[#kioclient_cmds + 1] = { kioclient, "move", path, "trash:/" }
      end
      return kioclient_cmds
    end,
  },
  windows = {
    { "trash" }, -- trash-cli, usually
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
        "$shell = New-Object -ComObject 'Shell.Application';",
        "$folder = $shell.NameSpace(0);",
      }
      for _, path in ipairs(p) do
        local escaped = path:gsub("\\", "\\\\"):gsub("'", "''")
        pwsh_cmds[#pwsh_cmds + 1] = ([[$path = Get-Item '%s'; $folder.ParseName($path.FullName).InvokeVerb('delete');]]):format(
          escaped
        )
      end
      cmd[#cmd + 1] = table.concat(pwsh_cmds, " ")
      return {
        cmd,
      }
    end,
  },
}

---@param cmds string[][]
---@return boolean success
---@return string[]? err
---@return integer? failed_at
local execute_trash_commands = function(cmds)
  for i, cmd in ipairs(cmds) do
    local success, err = utils.execute_command(cmd)
    if not success then
      return false, err, i
    end
  end
  return true
end

---@param paths string[]
---@return boolean success
---@return string? err
M.trash = function(paths)
  log.assert(#paths > 0)
  local commands = {
    require("neo-tree").ensure_config().trash.cmd,
  }
  if utils.is_macos then
    vim.list_extend(commands, builtins.macos)
  elseif utils.is_windows then
    vim.list_extend(commands, builtins.windows)
  else
    vim.list_extend(commands, builtins.linux)
  end

  ---@type string[][]
  for _, command in ipairs(commands) do
    repeat
      if type(command) == "function" then
        local res, err = command(paths)
        log.debug("Trash function result:", res, err)
        if not res then
          break -- try next command
        end

        if type(res) == "table" then
          local cmds = res
          local trash_ok, output, failed_at = execute_trash_commands(cmds)
          if not trash_ok then
            return false,
              "Trash commands failed at " .. table.concat(cmds[failed_at], " ") .. ":" .. output
          end

          log.debug("Trashed", paths, "using", cmds)
        elseif type(res) == "function" then
          local trash_ok, trashfunc_err = res()
          if not trash_ok then
            return false, "Trash function failed: " .. (trashfunc_err or "<no error returned>")
          end
          log.debug("Trashed", paths, "using function")
        end
        return true
      end

      if type(command) == "table" then
        if command.healthcheck then
          local command_ok, err = command.healthcheck(paths)
          if not command_ok then
            log.debug("Trash command", command, "failed healthcheck:", err)
            break -- try next command
          end
        elseif not utils.executable(command[1]) then
          log.debug("Trash command", command, "not executable")
          break -- try next command
        end

        local full_command = vim.list_extend({
          unpack(command),
        }, paths)
        log.debug("Running trash command", full_command)
        local trash_ok, output = execute_trash_commands({ full_command })
        if not trash_ok then
          return false, "Could not trash with " .. full_command .. ":" .. output
        end

        log.debug("Trashed", paths, "using", full_command)
        return true
      end

      return false, "Invalid trash command:" .. command
    until true
  end
  return false, "No trash commands or functions worked."
end

return M
