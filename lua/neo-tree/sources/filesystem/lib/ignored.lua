local M = {}

local uv = vim.uv or vim.loop
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local glob = require("neo-tree.sources.filesystem.lib.lua-glob")

---@class neotree.sources.filesystem.Ignore.Rule
---@field root string
---@field pattern string
---@field negate string

---@param path string
---@return neotree.lib.LuaGlob
local file_to_glob = function(path)
  ---@type string[]
  local lines = {}
  for line in io.lines(path) do
    local is_comment = line:sub(1, 1) == "#"
    if not is_comment then
      table.insert(lines, line)
    end
  end

  local parent_path = assert(utils.split_path(path))
  return glob.gitignore(lines, {
    root = parent_path,
  }, {
    type = function(p)
      local abspath = utils.path_join(parent_path, p)
      local kind = assert(uv.fs_stat(abspath)).type
      if kind == "directory" then
        return "directory"
      elseif kind == "file" then
        return "file"
      end
      return nil
    end,
  })
end

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

  ---@type table<string, { path: string, parser: neotree.lib.LuaGlob }[]>
  local ignorers = {}

  ---@type string[]
  local results = {}

  for folder, children in pairs(folders) do
    ignorers[folder] = ignorers[folder] or {}
    local folder_ignorers = ignorers[folder]
    local applicable_ignore_files =
      vim.fs.find(ignore_files, { upward = true, limit = math.huge, path = folder })

    for _, ignore_filepath in ipairs(applicable_ignore_files) do
      globs[ignore_filepath] = globs[ignore_filepath] or file_to_glob(ignore_filepath)
      folder_ignorers[#folder_ignorers + 1] = {
        path = ignore_filepath,
        parser = globs[ignore_filepath],
      }
    end

    for _, item in ipairs(children) do
      if not item.filtered_by or not item.filtered_by.ignore_file then
        for _, ignorer in ipairs(folder_ignorers) do
          local parser = ignorer.parser
          local ignored = parser:check(item.path)
          if ignored ~= nil then
            item.filtered_by = item.filtered_by or {}
            item.filtered_by.ignore_file = ignorer.path
            item.filtered_by.ignored = ignored
          end
        end
      end
    end
  end

  return results
end

return M
