local M = {}

local uv = vim.uv or vim.loop
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")

---@class neotree.sources.filesystem.Ignore.Rule
---@field root string
---@field pattern string
---@field negate string

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
  local upward_ignore_paths = {}

  ---@type table<string, string[]>
  local ignore_rules = {}
  for folder in pairs(folders) do
    local paths = vim.fs.find(ignore_files, { upward = true, limit = math.huge, path = folder })
    upward_ignore_paths[folder] = paths

    for _, path in ipairs(paths) do
      for line in io.lines(path) do
        if line:sub(1, 1) ~= "#" then
          ---@cast line string
          local negated = line:sub(1, 1) == "!"
          local pat = negated and line:sub(2) or line
        end
      end
    end
  end
end

if vim.fn.has("nvim-0.10") then
  -- make it a no-op
  M.mark_ignored = function() end
end

return M
