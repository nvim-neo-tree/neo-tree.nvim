local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local git_utils = require("neo-tree.git.utils")

local M = {}
local sep = utils.path_separator

M.is_ignored = function(ignored, path, _type)
  if _type == "directory" and not utils.is_windows then
    path = path .. sep
  end

  return vim.tbl_contains(ignored, path)
end

local git_root_cache = {
  known_roots = {},
  dir_lookup = {},
}
local get_root_for_item = function(item)
  local dir = item.type == "directory" and item.path or item.parent_path
  if type(git_root_cache.dir_lookup[dir]) ~= "nil" then
    return git_root_cache.dir_lookup[dir]
  end
  --for _, root in ipairs(git_root_cache.known_roots) do
  --  if vim.startswith(dir, root) then
  --    git_root_cache.dir_lookup[dir] = root
  --    return root
  --  end
  --end
  local root = git_utils.get_repository_root(dir)
  if root then
    git_root_cache.dir_lookup[dir] = root
    table.insert(git_root_cache.known_roots, root)
  else
    git_root_cache.dir_lookup[dir] = false
  end
  return root
end

M.mark_ignored = function(state, items)
  local folders = {}
  log.trace("================================================================================")
  log.trace("IGNORED: mark_ignore BEGIN...")
  for _, item in ipairs(items) do
    local folder = utils.split_path(item.path)
    if folder then
      if not folders[folder] then
        folders[folder] = {}
      end
      table.insert(folders[folder], item.path)
    end
  end

  local all_results = {}
  for folder, folder_items in pairs(folders) do
    local cmd = { "git", "-C", folder, "check-ignore" }
    for _, item in ipairs(folder_items) do
      table.insert(cmd, item)
    end
    log.trace("IGNORED: Running cmd: ", cmd)
    local result = vim.fn.systemlist(cmd)
    if vim.v.shell_error == 128 then
      log.debug("Failed to load ignored files for", state.path, ":", result)
      result = {}
    end

    if utils.is_windows then
      --on Windows, git seems to return quotes and double backslash "path\\directory"
      result = vim.tbl_map(function(item)
        item = item:gsub('"', "")
        item = item:gsub("\\\\", "\\")
        return item
      end, result)
    else
      --check-ignore does not indicate directories the same as 'status' so we need to
      --add the trailing slash to the path manually if not on Windows.
      log.trace("IGNORED: Checking types of", #result, "items to see which ones are directories")
      for i, item in ipairs(result) do
        local stat = vim.loop.fs_stat(item)
        if stat and stat.type == "directory" then
          result[i] = item .. sep
        end
      end
    end

    vim.list_extend(all_results, result)
  end

  local show_anyway = state.filtered_items and state.filtered_items.hide_gitignored == false
  log.trace("IGNORED: Comparing results to mark items as ignored, show_anyway:", show_anyway)
  local ignored, not_ignored = 0, 0
  for _, item in ipairs(items) do
    if M.is_ignored(all_results, item.path, item.type) then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.gitignored = true
      item.filtered_by.show_anyway = show_anyway
      ignored = ignored + 1
    else
      not_ignored = not_ignored + 1
    end
  end
  log.trace("IGNORED: mark_ignored is complete, ignored:", ignored, ", not ignored:", not_ignored)
  log.trace("================================================================================")
  return all_results
end

return M
