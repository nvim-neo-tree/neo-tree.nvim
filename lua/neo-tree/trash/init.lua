local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local freedesktop_trash = require("neo-tree.trash.freedesktop")
local windows_trash = require("neo-tree.trash.windows")
local M = {}

---@alias neotree.trash.Command neotree.trash.PureCommand|neotree.trash.FunctionGenerator|neotree.trash.CommandGenerator

---A convienient format to define a trash command with rm-like syntax.
---@class neotree.trash.PureCommand
---@field healthcheck? fun(paths: string[]):success: boolean, err: string?
---@field restorer? neotree.trash.Restorer
---@field [integer] string

---A function that may return trash commands to execute, in order.
---@alias neotree.trash.CommandGenerator fun(paths: string[]):(commands: string[][]?, restorer: neotree.trash.Restorer?)

---A function that may return a function that will do the trashing.
---@alias neotree.trash.FunctionGenerator fun(paths: string[]):(trashfunc: neotree.trash._Function?, restorer: neotree.trash.Restorer?)

---The internal function type that actually does the requisite trashing.
---@alias neotree.trash._Function fun():success: boolean

---@alias neotree.trash.Restorer neotree.trash.RestoreFunctionGenerator|neotree.trash.RestoreCommandGenerator

---A function that may return trash-restoring commands to execute, in order.
---@alias neotree.trash.RestoreCommandGenerator fun(trashed_paths: string[]):(string[][]?)

---A function that may return a function that will do the trash restoration.
---@alias neotree.trash.RestoreFunctionGenerator fun(trashed_paths: string[]):(neotree.trash._RestoreFunction?)

---A function that is supposed to restore any files deleted by a certain trash method.
---@alias neotree.trash._RestoreFunction fun():success: boolean

-- Using programs mentioned by
-- https://github.com/folke/snacks.nvim/blob/ed08ef1a630508ebab098aa6e8814b89084f8c03/lua/snacks/explorer/actions.lua

---A list of built-in trashers that are natively supported for trashing use.
---
---https://github.com/andreafrancia/trash-cli and kioclient are not featured because they doen't have a non-interactive way of restoring
---a selected list of items in the trash.
---@type table<string, neotree.trash.Command[]>
M._builtins = {
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
      restorer = function(trashed_paths)
        local _, trash_files_dir = require("neo-tree.trash.freedesktop").calculate_trash_paths()
        -- check that all trashed paths start with the dir
        local cmd = { "gio", "trash", "--restore" }
        for i, trashed_path in ipairs(trashed_paths) do
          if not utils.is_subpath(trash_files_dir, trashed_path) then
            return nil
          end
          local fname = trashed_path:sub(#trash_files_dir + 1)
          cmd[#cmd + 1] = "trash:///" .. fname
        end
        return { cmd }
      end,
    },
    freedesktop_trash.generate_trashfunc,
  },
  windows = {
    windows_trash.generate_recycle_commands,
  },
}

---Converts a list of commands to a function that runs them, in order, and without stopping on the first error.
---@param cmds string[][]
---@return neotree.trash._Function?
local commands_to_runnerfunc = function(cmds)
  assert(
    type(cmds[1]) == "table" and type(cmds[1][1]) == "string",
    "Trash command generator should have returned a non-empty string[][]."
  )
  return function()
    log.debug("Executing trash commands:", cmds)
    local all_succeeded = true
    for i, cmd in ipairs(cmds) do
      local success, output = utils.execute_command(cmd)
      if not success then
        local cmd_str = table.concat(cmd, "\n")
        local output_str = table.concat(output, "\n")
        log.at.warn.format("Command `%s` failed: %s", cmd_str, output_str)
        all_succeeded = false
      end
    end
    return all_succeeded
  end
end

---If both returns are nil, then skip.
---@param paths string[]
---@param command neotree.trash.Command
---@return neotree.trash._Function? trashfunc
---@return string? err
---@return neotree.trash.Restorer? restorer
local normalize_trash_command_to_function = function(paths, command)
  if type(command) == "table" then
    local cmd = { unpack(command) }
    vim.list_extend(cmd, paths)
    if not utils.executable(cmd[1]) then
      return nil, nil
    end
    if type(command.healthcheck) == "function" then
      local healthy, err = command.healthcheck(paths)
      if not healthy then
        if err then
          log.at.debug.format(
            "Issue with trash command `%s`: %s, trying next trash command",
            cmd[1],
            err
          )
        end
        return nil, nil
      end
    end

    return commands_to_runnerfunc({ cmd }), nil, command.restorer
  end

  if type(command) == "function" then
    local trashfunc
    local res, restorer = command(paths)
    if res == nil then
      return nil, nil
    elseif type(res) == "table" then
      trashfunc = commands_to_runnerfunc(res)
    elseif type(res) == "function" then
      trashfunc = res
    else
      return nil,
        "Invalid return type from trash function generator, expected string[][]|function|nil"
    end
    return trashfunc, nil, restorer
  end

  return nil, "Unable to determine trashing method from command"
end

---@param paths string[]
---@return boolean success
---@return string? err
---@return neotree.trash.Restorer? restorer The corresponding restore functionality for the method used to trash.
M.trash = function(paths)
  log.assert(#paths > 0)
  local commands = {
    require("neo-tree").ensure_config().trash.command,
  }
  if utils.is_macos then
    vim.list_extend(commands, M._builtins.macos)
  elseif utils.is_windows then
    vim.list_extend(commands, M._builtins.windows)
  else
    vim.list_extend(commands, M._builtins.linux)
  end

  for _, command in ipairs(commands) do
    local trashfunc, normalize_err, restorer = normalize_trash_command_to_function(paths, command)
    if normalize_err then
      return false, normalize_err
    end
    if trashfunc then
      local success, err, restorer_from_trashfunc = trashfunc()
      return success, err, restorer_from_trashfunc or restorer
    end
  end
  return false, "No trash commands or functions worked."
end

---Attempt to restore files from trash.
---@param paths string[]
---@param restorer neotree.trash.Restorer? Either an explicit restorer for the given paths, or Neo-tree
---will attempt to guess at the correct restorer.
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
        restorer = freedesktop_trash.generate_restorer
      else
        return false, "Couldn't find a supported trash restore method for the given paths"
      end
    end
  end
  if type(restorer) ~= "function" then
    return false,
      "restorer: expected function (@type neotree.trash.Restore), got a " .. type(restorer)
  end

  local res, err = restorer(paths)
  if not res then
    vim.print({ restorer, paths, freedesktop_trash, res, err })
    return false, err
  end
  local restorefunc
  if type(res) == "table" then
    restorefunc = commands_to_runnerfunc(res)
  elseif type(res) == "function" then
    restorefunc = res
  end
  if not restorefunc then
    return false
  end
  return restorefunc()
end

return M
