local Path = require("plenary.path")
local utils = require("neo-tree.utils")
local events = require("neo-tree.events")
local Job = require("plenary.job")
local log = require("neo-tree.log")
local git_utils = require("neo-tree.git.utils")

local M = {}

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

local parse_git_status_line = function(context, line)
  local git_root = context.git_root
  local git_status = context.git_status
  local exclude_directories = context.exclude_directories

  local status = line:sub(1, 2)
  local relative_path = line:sub(4)
  local arrow_pos = relative_path:find(" -> ")
  if arrow_pos ~= nil then
    relative_path = line:sub(arrow_pos + 5)
  end
  -- remove any " due to whitespace in the path
  relative_path = relative_path:gsub('^"', ""):gsub('$"', "")
  if utils.is_windows == true then
    relative_path = utils.windowize_path(relative_path)
  end
  local absolute_path = utils.path_join(git_root, relative_path)
  git_status[absolute_path] = status

  if not exclude_directories then
    -- Now bubble this status up to the parent directories
    local parts = utils.split(absolute_path, utils.path_separator)
    table.remove(parts) -- pop the last part so we don't override the file's status
    utils.reduce(parts, "", function(acc, part)
      local path = acc .. utils.path_separator .. part
      if utils.is_windows == true then
        path = path:gsub("^" .. utils.path_separator, "")
      end
      local path_status = git_status[path]
      local file_status = get_simple_git_status_code(status)
      git_status[path] = get_priority_git_status_code(path_status, file_status)
      return path
    end)
  end
end

local parse_git_status = function(git_root, result, exclude_directories)
  local context = {
    git_root = git_root,
    git_status = {},
    exclude_directories = exclude_directories,
  }
  for _, line in ipairs(result) do
    parse_git_status_line(context, line)
  end
  return context.git_status
end

---Parse "git status" output for the current working directory.
---@exclude_directories boolean Whether to skip bubling up status to directories
---@path string Path to run the git status command in, defaults to cwd.
---@return table table Table with the path as key and the status as value.
---@return string string The git root for the specified path.
M.status = function(exclude_directories, path)
  local cmd
  local git_root = git_utils.get_repository_root(path)
  if utils.truthy(git_root) then
    cmd = 'git -C "' .. git_root .. '" status . --porcelain=v1'
  else
    return {}
  end

  local ok, result = utils.execute_command(cmd)
  if not ok then
    return {}
  end
  local git_status = parse_git_status(git_root, result, exclude_directories)
  return git_status, git_root
end

M.status_async = function(path)
  local git_root = git_utils.get_repository_root(path)
  if utils.truthy(git_root) then
    log.trace("git.status.status_async called")
  else
    log.trace("status_async: not a git folder: ", path)
    return false
  end

  local context = {
    git_root = git_root,
    git_status = {},
    exclude_directories = false,
  }
  local wrapped_process_line = vim.schedule_wrap(function(err, line)
    if err and err > 0 then
      log.error("status_async error: ", err, line)
    else
      parse_git_status_line(context, line)
    end
  end)

  local event_id = "git_status_" .. git_root
  utils.debounce(event_id, function()
    Job
      :new({
        command = "git",
        args = { "-C", git_root, "status", "--porcelain=v1" },
        enable_recording = false,
        on_stdout = wrapped_process_line,
        on_stderr = function(err, line)
          if err and err > 0 then
            log.error("status_async error: ", err, line)
          end
        end,
        on_exit = function(job, return_val)
          utils.debounce(event_id, nil, nil, nil, utils.debounce_action.COMPLETE_ASYNC_JOB)
          if return_val == 0 then
            log.trace("status_async completed")
            vim.schedule(function()
              events.fire_event(events.GIT_STATUS_CHANGED, {
                git_root = context.git_root,
                git_status = context.git_status,
              })
            end)
          end
        end,
      })
      :start()
  end, 1000, utils.debounce_strategy.CALL_FIRST_AND_LAST, utils.debounce_action.START_ASYNC_JOB)

  return true
end

return M
