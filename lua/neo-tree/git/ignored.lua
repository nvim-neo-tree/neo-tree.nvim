local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local git_utils = require("neo-tree.git.utils")

local M = {}
local sep = utils.path_separator

M.is_ignored = function(ignored, path, _type)
  path = _type == "directory" and (path .. sep) or path
  for _, v in ipairs(ignored) do
    if v:sub(-1) == utils.path_separator or (utils.is_windows and _type == "directory") then
      -- directory ignore
      if vim.startswith(path, v) then
        return true
      end
    else
      -- file ignore
      if path == v then
        return true
      end
    end
  end
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
  for _, root in ipairs(git_root_cache.known_roots) do
    if vim.startswith(dir, root) then
      git_root_cache.dir_lookup[dir] = root
      return root
    end
  end
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
  local git_roots = {}
  for _, item in ipairs(items) do
    local root = get_root_for_item(item)
    if root then
      if not git_roots[root] then
        git_roots[root] = {}
      end
      table.insert(git_roots[root], item.path)
    end
  end

  local all_results = {}
  for repo_root, repo_items in pairs(git_roots) do
    local cmd = {"git", "-C", repo_root, "check-ignore"}
    for _, item in ipairs(repo_items) do
      table.insert(cmd, item)
    end
    local result = vim.fn.systemlist(cmd)
    if vim.v.shell_error == 128 then
      if type(result) == "table" then
        if vim.startswith(result[1], "fatal:") then
          -- These errors are all about not being in a repository
          log.error("Error in git.mark_ignored: ", result[1])
          result = {}
        end
      end
      log.error("Failed to load ignored files for", state.path, ":", result)
      result = {}
    end

    --check-ignore does not indicate directories the same as 'status' so we need to
    --add the trailing slash to the path manually.
    for i, item in ipairs(result) do
      local stat = vim.loop.fs_stat(item)
      if stat and stat.type == "directory" then
        result[i] = item .. sep
      end
    end
    vim.list_extend(all_results, result)
  end


  for _, item in ipairs(items) do
    if M.is_ignored(all_results, item.path, item.type) then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.gitignored = true
    end
  end

  return all_results
end

return M
