local M = {}

local uv = vim.uv or vim.loop
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")

---@class neotree.Ignore
---@field pattern string
---@field exclude string

---@param state neotree.State
---@param items neotree.FileItem[]
---@param callback nil
---@return string[] results
---@overload fun(state: neotree.State, items: neotree.FileItem, callback: fun(results: string[]))
M.mark_ignored = function(state, items, callback)
  local config = require("neo-tree").config
  local ignore_files = config.filesystem.filtered_items.ignore_files
  if not ignore_files or vim.tbl_isempty(config.filesystem.filtered_items.ignore_files) then
    return {}
  end
  ---@type table<string, string[]>
  local folders = {}

  for _, item in ipairs(items) do
    local folder = utils.split_path(item.path)
    if folder then
      folders[folder] = folders[folder] or {}
      table.insert(folders[folder], item.path)
    end
  end

  ---@type table<string, string[]>
  local upward_ignore_files = {}
  local ignore_file_contents = {}
  for folder, folder_items in pairs(folders) do
    upward_ignore_files[folder] =
      vim.fs.find(ignore_files, { upward = true, limit = math.huge, path = folder })

    for _, file in ipairs(upward_ignore_files[folder]) do
      local fd, err, code = uv.fs_open(file, "r")
      if fd then
      else
        log.warn()
      end
    end
  end
end

return M
