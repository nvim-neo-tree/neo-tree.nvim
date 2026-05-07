local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local M = {}

---@param gvfs_paths string[]
---@return boolean
local restore = function(gvfs_paths)
  local restore_ok =
    utils.execute_command(vim.list_extend({ "gio", "trash", "--restore" }, gvfs_paths))
  return restore_ok
end

---@return [string, string][]? entries
local list_entries = function()
  local list_ok, before_list_output = utils.execute_command({ "gio", "trash", "--list" })
  if not list_ok then
    log.at.warn.format("Error with `gio trash --list`: %s", table.concat(before_list_output, "\n"))
    return nil
  end
  local list = {}
  for _, line in ipairs(before_list_output) do
    local tab_index = line:find("\t", 1, true)
    if tab_index then
      local trash_filepath = line:sub(1, tab_index - 1)
      local original_filepath = line:sub(tab_index + 1)
      list = { trash_filepath, original_filepath }
    end
  end
  return list
end

---@type neotree.trash.FunctionGenerator
M.generate_trashfunc = function(paths)
  if not utils.executable("gio") then
    return nil
  end

  local before_list = list_entries()
  if not before_list then
    return nil
  end
  return function()
    local trash_ok, trash_output = utils.execute_command(vim.list_extend({ "gio", "trash" }, paths))
    if not trash_ok then
      log.at.warn.format("Error with `gio trash`: %s", table.concat(trash_output, "\n"))
    end

    local was_in_before_list = {}
    for _, entry in ipairs(before_list) do
      was_in_before_list[entry[1]] = entry[2]
    end

    local after_list = list_entries()
    if not after_list then
      return false
    end

    local new_trash_items = {}
    for _, entry in ipairs(after_list) do
      local trash_filepath = entry[1]
      if not was_in_before_list[trash_filepath] then
        new_trash_items[#new_trash_items + 1] = trash_filepath
      end
    end
    ---@type neotree.trash.RestoreInternalFunction
    local restorefunc = function()
      return restore(new_trash_items)
    end
    return true, restorefunc
  end
end
return M
