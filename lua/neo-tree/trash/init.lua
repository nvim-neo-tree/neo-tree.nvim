local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local freedesktop_trash = require("neo-tree.trash.freedesktop")
local gio_trash = require("neo-tree.trash.gio")
local windows_trash = require("neo-tree.trash.windows")
local M = {}

---@alias neotree.trash.Command neotree.trash.PureCommand|neotree.trash.FunctionGenerator|neotree.trash.CommandGenerator

---A convienient format to define a trash command with rm-like syntax.
---@class neotree.trash.PureCommand
---@field restorer? neotree.trash.Restorer
---@field [integer] string

---A function that may return trash commands to execute, in order.
---@alias neotree.trash.CommandGenerator fun(paths: string[]):(commands: string[][]?)

---A function that may return a function that will do the trashing.
---@alias neotree.trash.FunctionGenerator fun(paths: string[]):(trashfunc: neotree.trash._Function?)

---The internal function type that actually does the requisite trashing.
---@alias neotree.trash._Function fun():(success: boolean, restorefunc: neotree.trash._RestoreFunction?)

---@alias neotree.trash.Restorer neotree.trash.RestoreFunctionGenerator|neotree.trash.RestoreCommandGenerator

---A function that may return trash-restoring commands to execute, in order.
---@alias neotree.trash.RestoreCommandGenerator fun(trashed_paths: string[]):(commands: string[][]?)

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
    gio_trash.generate_trashfunc,
    freedesktop_trash.generate_trashfunc,
  },
  windows = {
    windows_trash.generate_recycle_commands,
  },
}

---Converts a list of commands to a function that runs them, in order, and without stopping on the first error.
---@param cmds string[][]
---@return fun():(success: boolean)?
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
---@return neotree.State.UndoFunction? undoer
local normalize_trash_command_to_function = function(paths, command)
  if type(command) == "table" then
    local cmd = { unpack(command) }
    vim.list_extend(cmd, paths)
    if not utils.executable(cmd[1]) then
      return nil, nil
    end

    return commands_to_runnerfunc({ cmd })
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
---@return neotree.trash._RestoreFunction? restorefunc A function that, when called, should "undo" the trash operation.
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
    local trashfunc, normalize_err, restorefunc =
      normalize_trash_command_to_function(paths, command)
    if normalize_err then
      return false, normalize_err
    end
    if trashfunc then
      local success, restorefunc_from_trashfunc = trashfunc()
      return success, nil, restorefunc_from_trashfunc or restorefunc
    end
  end
  return false, "No trash commands or functions worked."
end

---Attempt to restore files from trash.
---@param trashed_paths string[]
---@param restorer neotree.trash.Restorer? Either an explicit restorer for the given paths, or Neo-tree will attempt to guess at the correct restorer.
---@return boolean success
---@return string? err
M.restore = function(trashed_paths, restorer)
  if not restorer then
    -- determine how to restore the files
    if utils.is_macos then
      return false, "Restoring from trash on macOS is not supported"
    end

    if utils.is_windows then
      restorer = windows_trash.generate_restore_commands
    else
      local _, trash_files_dir = freedesktop_trash.calculate_trash_paths()
      if not trash_files_dir then
        return false, "Couldn't determine XDG trash paths, not restoring"
      end
      for _, trashed_path in ipairs(trashed_paths) do
        if not utils.is_subpath(trash_files_dir, trashed_path) then
          log.at.warn.format(
            "File %s isn't in XDG trash files directory %s, skipping",
            trashed_path,
            trash_files_dir
          )
        end
      end
      restorer = freedesktop_trash.generate_restorer
    end
  end
  if type(restorer) ~= "function" then
    return false,
      "restorer: expected function (@type neotree.trash.Restore), got a " .. type(restorer)
  end

  local res, err = restorer(trashed_paths)
  if not res then
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
