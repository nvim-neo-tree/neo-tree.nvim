local Path = require("plenary.path")
local utils = require("neo-tree.utils")

local os_sep = Path.path.sep

local M = {}

local function execute_command(cmd)
  local result = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 or vim.startswith(result[1], "fatal:") then
    return false, {}
  else
    return true, result
  end
end

local function windowize_path(path)
  return path:gsub("/", "\\")
end

M.get_repository_root = function(path)
  local cmd = "git rev-parse --show-toplevel"
  if utils.truthy(path) then
    cmd = "git -C " .. path .. " rev-parse --show-toplevel"
  end
  local ok, git_root = execute_command(cmd)
  if not ok then
    return nil
  end
  git_root = git_root[1]

  if utils.is_windows then
    git_root = windowize_path(git_root)
  end

  return git_root
end

local function get_simple_git_status_code(status)
  -- Prioritze M then A over all others
  if status:match("U") or status == "AA" or status == "DD" then
    return "U"
  elseif status:match("M") then
    return "M"
  elseif status:match("[ACR]") then
    return "A"
  elseif status:match("!$") then
    return "!"
  elseif status:match("?$") then
    return "?"
  else
    local len = #status
    while len > 0 do
      local char = status:sub(len, len)
      if char ~= " " then
        return char
      end
      len = len - 1
    end
    return status
  end
end

local function get_priority_git_status_code(status, other_status)
  if not status then
    return other_status
  elseif not other_status then
    return status
  elseif status == "U" or other_status == "U" then
    return "U"
  elseif status == "?" or other_status == "?" then
    return "?"
  elseif status == "M" or other_status == "M" then
    return "M"
  elseif status == "A" or other_status == "A" then
    return "A"
  else
    return status
  end
end

---Parse "git status" output for the current working directory.
---@return table table Table with the path as key and the status as value.
M.status = function(exclude_directories)
  local git_root = M.get_repository_root()
  if not git_root then
    return {}
  end
  local ok, result = execute_command("git status --porcelain=v1")
  if not ok then
    return {}
  end

  local git_status = {}
  for _, line in ipairs(result) do
    local status = line:sub(1, 2)
    local relative_path = line:sub(4)
    local arrow_pos = relative_path:find(" -> ")
    if arrow_pos ~= nil then
      relative_path = line:sub(arrow_pos + 5)
    end
    -- remove any " due to whitespace in the path
    relative_path = relative_path:gsub('^"', ""):gsub('$"', "")
    if utils.is_windows == true then
      relative_path = windowize_path(relative_path)
    end
    local absolute_path = string.format("%s%s%s", git_root, os_sep, relative_path)
    git_status[absolute_path] = status

    if not exclude_directories then
      -- Now bubble this status up to the parent directories
      local file_status = get_simple_git_status_code(status)
      local parents = Path:new(absolute_path):parents()
      for i = #parents, 1, -1 do
        local path = parents[i]
        local path_status = git_status[path]
        git_status[path] = get_priority_git_status_code(path_status, file_status)
      end
    end
  end

  return git_status, git_root
end

M.load_ignored = function(path)
  local git_root = M.get_repository_root(path)
  if not git_root then
    return {}
  end
  local ok, result = execute_command(
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
        entry = windowize_path(entry)
      end
      -- use the absolute path
      table.insert(ignored, string.format("%s%s%s", git_root, os_sep, entry))
    end
  end

  return ignored
end

M.is_ignored = function(ignored, path, _type)
  path = _type == "directory" and (path .. os_sep) or path
  for _, v in ipairs(ignored) do
    if v:sub(-1) == os_sep then
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
