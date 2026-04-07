local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local freedesktop_trash = require("neo-tree.trash.freedesktop")
local windows_trash = require("neo-tree.trash.windows")
local M = {}

---@alias neotree.trash.Command neotree.trash.PureCommand|neotree.trash.FunctionGenerator|neotree.trash.CommandGenerator

---A convienient format to define a trash command with rm-like syntax.
---@class neotree.trash.PureCommand
---@field healthcheck? neotree.trash.PureCommand.HealthCheck
---@field restore? neotree.trash._Restorer
---@field [integer] string

---@alias neotree.trash.PureCommand.HealthCheck fun(paths: string[]):success: boolean, err: string?

---A function that may return trash commands to execute, in order.
---@alias neotree.trash.CommandGenerator fun(paths: string[]):(string[][]?)

---A function that may return a function that will do the trashing.
---@alias neotree.trash.FunctionGenerator fun(paths: string[]):(neotree.trash._Function?)

---The internal function type that actually does the requisite trashing.
---@alias neotree.trash._Function fun():success: boolean, err: string?, restore: neotree.trash._Restorer?

---@alias neotree.trash.Restore neotree.trash.RestoreFunctionGenerator|neotree.trash.RestoreCommandGenerator

---A function that may return trash-restoring commands to execute, in order.
---@alias neotree.trash.RestoreCommandGenerator fun(paths: string[]):(string[][]?)

---A function that may return a function that will do the trash restoration.
---@alias neotree.trash.RestoreFunctionGenerator fun(paths: string[]):(neotree.trash._Function?)

---A function that is supposed to restore any files deleted by a certain trash method.
---@alias neotree.trash._Restorer fun():success: boolean, err: string?

-- Using programs mentioned by
-- https://github.com/folke/snacks.nvim/blob/ed08ef1a630508ebab098aa6e8814b89084f8c03/lua/snacks/explorer/actions.lua

---A list of built-in trashers that are natively supported for trashing use.
---
---https://github.com/andreafrancia/trash-cli is not featured because it doesn't have a non-interactive way of restoring
---a selected list of items in the trash.
---@type table<string, neotree.trash.Command[]>
M._trash_builtins = {
  macos = {
    { "trash" }, -- either the macOS 15 built-in, or someone's better replacment.
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
        if not utils.execute_command({ "gio", "trash", "--list" }) then
          return false, "Could not run `gio trash --list`, check if gvfs is installed"
        end
        return true
      end,
      ---@type neotree.trash.RestoreCommandGenerator
      restore = function(trashed_paths)
        local trash_dir = require("neo-tree.trash.freedesktop").calculate_trash_paths()
        -- check that all trashed paths start with the dir
        local cmds = {}
        for i, p in ipairs(trashed_paths) do
          if utils.is_subpath(trash_dir, p) then
            return nil
          end
        end
        return function()
          return cmds
        end
      end,
    },
    freedesktop_trash.new_trasher,
  },
  windows = {
    windows_trash.generate_recycle_commands,
  },
}

---@param cmds string[][]
---@return neotree.trash._Function?
local commands_to_runnerfunc = function(cmds)
  return function()
    log.debug("Executing trash commands:", cmds)
    for i, cmd in ipairs(cmds) do
      local success, output = utils.execute_command(cmd)
      if not success then
        local failed_command_string = table.concat(cmd, " ")
        if #cmds > 1 then
          return false, ("Trash commands failed at `%s`: %s"):format(failed_command_string, output)
        else
          return false, ("Trash command `%s` failed: %s"):format(failed_command_string, output)
        end
      end
    end
    return true
  end
end

---@param paths string[]
---@return boolean success
---@return string? err
---@return neotree.trash._Restorer? restore An undo function.
M.trash = function(paths)
  log.assert(#paths > 0)
  local commands = {
    require("neo-tree").ensure_config().trash.command,
  }
  if utils.is_macos then
    vim.list_extend(commands, M._trash_builtins.macos)
  elseif utils.is_windows then
    vim.list_extend(commands, M._trash_builtins.windows)
  else
    vim.list_extend(commands, M._trash_builtins.linux)
  end

  for _, command in ipairs(commands) do
    repeat
      local trashfunc
      if type(command) == "table" then
        local cmd = { unpack(command) }
        vim.list_extend(cmd, paths)
        if not utils.executable(cmd[1]) then
          break -- next cmd
        end
        if type(command.healthcheck) == "function" then
          local healthy, err = command.healthcheck(paths)
          if not healthy then
            if err then
              log.at.warn.format(
                "Issue with trash command `%s`: %s, %s",
                cmd[1],
                err,
                "trying next trash command"
              )
            end
            break -- next command
          end
        end

        trashfunc = commands_to_runnerfunc({ cmd })
      elseif type(command) ~= "function" then
        local res, err = command(paths)
        if res == nil then
          if err then
            log.warn(err, ", trying next trash command")
          end
          break -- next command
        end

        if type(res) == "table" then
          ---We returned a list of commands to execute verbatim.
          ---@cast res string[][]
          assert(
            type(res[1]) == "table" and type(res[1][1]) == "string",
            "Trash command generator should have returned a string[][]."
          )
          trashfunc = commands_to_runnerfunc(res)
        elseif type(res) == "function" then
          trashfunc = res
        else
          return false,
            "Invalid return type from trash function generator, expected string[][]|function|nil"
        end
      end

      if not trashfunc then
        break -- next command
      end

      return trashfunc()
    until true
  end
  return false, "No trash commands or functions worked."
end

---Attempt to restore files from trash.
---@param paths string[]
---@param restorer neotree.trash.Restore? Either an explicit restorer for the given paths, or neo-tree
---will attempt to guess how to restore.
---@return boolean success
---@return string? err
M.restore = function(paths, restorer)
  if not restorer then
    -- determine how to restore the files
    if utils.is_macos then
      return false, "Restoring from trash on macOS is not supported"
    end

    if utils.is_windows then
      restorer = windows_trash.generate_restore_commands
    else
      local xdg_trash_dir = freedesktop_trash.calculate_trash_paths()
      if xdg_trash_dir then
        restorer = freedesktop_trash.new_restorer
      end
    end
  end
end

return M
