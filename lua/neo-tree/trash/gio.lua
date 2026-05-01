local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local M = {}

---@param gvfs_paths string[]
local restore = function(gvfs_paths)
  local restore_ok =
    utils.execute_command(vim.list_extend({ "gio", "trash", "--restore" }, gvfs_paths))
  return restore_ok
end

---@type neotree.trash.FunctionGenerator
M.generate_trashfunc = function(paths)
  if not utils.executable("gio") then
    return nil
  end
  local list_ok, before_list_output = utils.execute_command({ "gio", "trash", "--list" })
  if not list_ok then
    log.at.warn.format("Error with `gio trash --list`: %s", table.concat(before_list_output, "\n"))
    return nil
  end
  local trashmap = {}
  for _, line in ipairs(before_list_output) do
    local tab_index = line:find("\t", 1, true)
    if tab_index then
      local trash_filepath = line:sub(1, tab_index - 1)
      local original_filepath = line:sub(tab_index + 1)
      trashmap[trash_filepath] = original_filepath
    end
  end
  return function()
    local trash_ok, trash_output = utils.execute_command(vim.list_extend({ "gio", "trash" }, paths))
    if not trash_ok then
      log.at.warn.format("Error with `gio trash`: %s", table.concat(trash_output, "\n"))
    end

    local after_trash_ok, after_list_output = utils.execute_command({ "gio", "trash", "--list" })
    if not after_trash_ok then
      log.at.warn.format(
        "Error with 2nd `gio trash --list`: %s",
        table.concat(after_list_output, "\n")
      )
    end
    local new_trash_items = {}
    for _, line in ipairs(after_list_output) do
      local tab_index = line:find("\t", 1, true)
      if tab_index then
        local trash_filepath = line:sub(1, tab_index - 1)
        if not trashmap[trash_filepath] then
          new_trash_items[#new_trash_items + 1] = trash_filepath
        end
      end
    end
    ---@type neotree.trash._RestoreFunction
    local restorefunc = function()
      return restore(new_trash_items)
    end
    return true, restorefunc
  end
end
return M
