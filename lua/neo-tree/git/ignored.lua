local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local git_utils = require("neo-tree.git.utils")

local M = {}

M.load_ignored_per_directory = function(path)
  if type(path) ~= "string" then
    log.error("load_ignored_per_directory: path must be a string")
    return {}
  end
  path = utils.path_join(path, "*")
  local cmd = 'git check-ignore "' .. path .. '"'
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error == 128 then
    if utils.truthy(result) and vim.startswith(result[1], "fatal: not a git repository") then
      return {}
    end
    log.error("Failed to load ignored files for ", path, ": ", result)
    return {}
  end
  return result
end

M.load_ignored = function(path)
  local git_root = git_utils.get_repository_root(path)
  if not git_root then
    return {}
  end
  local ok, result = utils.execute_command(
    "git --no-optional-locks status --porcelain=v1 --ignored=matching --untracked-files=normal"
  )
  if not ok then
    return {}
  end

  local ignored = {}
  for _, v in ipairs(result) do
    -- git ignore format:
    -- !! path/to/file
    -- !! path/to/path/
    -- with paths relative to the repository root
    if v:sub(1, 2) == "!!" then
      local entry = v:sub(4)
      -- remove any " due to whitespace in the path
      entry = entry:gsub('^"', ""):gsub('$"', "")
      if utils.is_windows then
        entry = utils.windowize_path(entry)
      end
      -- use the absolute path
      table.insert(ignored, utils.path_join(git_root, entry))
    end
  end

  return ignored
end

M.is_ignored = function(ignored, path, _type)
  path = _type == "directory" and (path .. utils.path_separator) or path
  for _, v in ipairs(ignored) do
    if v:sub(-1) == utils.path_separator then
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

return M
