local M = {}

local uv = vim.uv or vim.loop
local utils = require("neo-tree.utils")
local glob = require("neo-tree.sources.filesystem.lib.lua-glob")
local log = require("neo-tree.log")

---Cached tuples of mtime (ns), inode, glob
---@type table<string, [integer, integer, neotree.lib.LuaGlob]>
local cache = {}

---@param path string
---@param root string
---@param stat uv.fs_stat.result
---@return neotree.lib.LuaGlob
local file_to_glob = function(path, root, stat)
  local mtime_ns = stat.mtime.nsec
  local inode = stat.ino

  local cached = cache[path]
  if cached then
    local cached_mtime_ns, cached_inode, cached_glob = unpack(cached)
    -- check if mtime/inode ok
    if cached_mtime_ns == mtime_ns and cached_inode == inode then
      return cached_glob
    end
  end

  ---@type string[]
  local lines = {}
  for line in io.lines(path) do
    local is_comment = line:sub(1, 1) == "#"
    if not is_comment then
      table.insert(lines, line)
    end
  end

  local glob_for_file = glob.gitignore(lines, {
    root = root,
  }, {
    type = function(p)
      local abspath = utils.path_join(root, p)
      local kind = assert(uv.fs_stat(abspath)).type
      if kind == "directory" then
        return "directory"
      elseif kind == "file" then
        return "file"
      end
      return nil
    end,
  })
  cache[path] = { mtime_ns, inode, glob_for_file }
  return glob_for_file
end

---@param relpaths string[]
---@param dir string
---@return neotree.sources.filesystem.Ignorer[]
local find_ignorers_in_dir = function(relpaths, dir)
  local found = {}
  for _, relpath in ipairs(relpaths) do
    local fullpath = utils.path_join(dir, relpath)
    local stat = uv.fs_stat(fullpath)
    if stat and stat.type == "file" then
      ---@class neotree.sources.filesystem.Ignorer
      local ignorer = {
        fullpath,
        file_to_glob(fullpath, dir, stat),
        dir,
      }
      found[#found + 1] = ignorer
    end
  end
  return found
end

---@param state neotree.State
---@param items neotree.FileItem[]
---@return nil
M.mark_ignored = function(state, items)
  local ignore_files = state.filtered_items.ignore_files
  if not ignore_files or vim.tbl_isempty(ignore_files) then
    return {}
  end
  ---@type table<string, neotree.FileItem[]>
  local folders = {}

  for _, item in ipairs(items) do
    local parent = utils.split_path(item.path)
    if parent then
      folders[parent] = folders[parent] or {}
      table.insert(folders[parent], item)
    end
  end

  ---@type table<string, neotree.sources.filesystem.Ignorer[]>
  local ignorers = {}

  for folder, children in pairs(folders) do
    ---@type neotree.sources.filesystem.Ignorer[]
    local applicable_ignorers = {}
    ---@type string?
    local parent = folder
    while parent do
      local ignorers_in_parent = ignorers[parent]
      if not ignorers_in_parent then
        ignorers_in_parent = find_ignorers_in_dir(ignore_files, parent)
        ignorers[parent] = ignorers_in_parent
      end
      vim.list_extend(applicable_ignorers, ignorers_in_parent)

      parent = utils.split_path(parent)
    end

    for _, item in ipairs(children) do
      if not item.filtered_by or not item.filtered_by.ignore_file then
        for _, ignorer in ipairs(applicable_ignorers) do
          local path, parser, root = unpack(ignorer)
          if utils.is_subpath(root, item.path) then
            local ignored = parser:check(item.path)
            if ignored ~= nil then
              item.filtered_by = item.filtered_by or {}
              item.filtered_by.ignore_file = path
              item.filtered_by.ignored = ignored
            end
          end
        end
      end
    end
  end
end

return M
