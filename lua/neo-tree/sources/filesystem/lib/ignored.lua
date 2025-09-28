local M = {}

local uv = vim.uv or vim.loop
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local glob = require("neo-tree.sources.filesystem.lib.lua-glob")

---@class neotree.sources.filesystem.Ignore.Rule
---@field root string
---@field pattern string
---@field negate string

---@param state neotree.State
---@param items neotree.FileItem[]
---@return string[] results
M.mark_ignored = function(state, items)
  local config = require("neo-tree").config
  local ignore_files = config.filesystem.filtered_items.ignore_files
  if not ignore_files or vim.tbl_isempty(config.filesystem.filtered_items.ignore_files) then
    return {}
  end
  ---@type table<string, neotree.FileItem[]>
  local folders = {}

  for _, item in ipairs(items) do
    local folder = utils.split_path(item.path)
    if folder then
      folders[folder] = folders[folder] or {}
      table.insert(folders[folder], item)
    end
  end

  ---@type table<string, neotree.lib.LuaGlob>
  local globs = {}

  ---@type table<string, neotree.lib.LuaGlob[]>
  local applicable_globs = {}

  ---@type string[]
  local results = {}

  for folder, children in pairs(folders) do
    applicable_globs[folder] = applicable_globs[folder] or {}
    local applicable_ignore_files =
      vim.fs.find(ignore_files, { upward = true, limit = math.huge, path = folder })

    for _, ignore_filepath in ipairs(applicable_ignore_files) do
      globs[ignore_filepath] = globs[ignore_filepath] or {}

      if not globs[ignore_filepath] then
        -- Create a glob for the ignore file
        for line in io.lines(ignore_filepath) do
          local is_comment = line:sub(1, 1) ~= "#"
          if not is_comment then
            table.insert(globs[ignore_filepath], line)
          end
        end

        local parent_path = utils.split_path(ignore_filepath)
        globs[ignore_filepath] = glob.gitignore(globs, { root = parent_path })
      end

      table.insert(applicable_globs[folder], globs[ignore_filepath])
    end

    for _, item in ipairs(children) do
      if not item.filtered_by or not item.filtered_by.ignored then
        for _, parser in ipairs(applicable_globs[folder]) do
          if parser:check(item.path) then
            item.filtered_by = item.filtered_by or {}
            item.filtered_by.ignored = true
          end
        end
      end
    end
  end

  return results
end

return M
