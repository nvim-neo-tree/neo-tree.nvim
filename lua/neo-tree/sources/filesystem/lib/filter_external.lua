local vim = vim
local log = require("neo-tree.log")
local Job = require("plenary.job")

local M = {}
local fd_supports_max_results = nil

local test_for_max_results = function(cmd)
  if fd_supports_max_results == nil then
    if cmd == "fd" or cmd == "fdfind" then
      --test if it supports the max-results option
      local test = vim.fn.system(cmd .. " this_is_only_a_test --max-depth=1 --max-results=1")
      if test:match("^error:") then
        fd_supports_max_results = false
        log.debug(cmd, "does NOT support max-results")
      else
        fd_supports_max_results = true
        log.debug(cmd, "supports max-results")
      end
    end
  end
end

local get_find_command = function(state)
  if state.find_command then
    test_for_max_results(state.find_command)
    return state.find_command
  end

  if 1 == vim.fn.executable("fd") then
    state.find_command = "fd"
  elseif 1 == vim.fn.executable("fdfind") then
    state.find_command = "fdfind"
  elseif 1 == vim.fn.executable("find") and vim.fn.has("win32") == 0 then
    state.find_command = "find"
  elseif 1 == vim.fn.executable("where") then
    state.find_command = "where"
  end

  test_for_max_results(state.find_command)
  return state.find_command
end

M.find_files = function(opts)
  local filters = opts.filters
  local limit = opts.limit or 200
  local cmd = get_find_command(opts)
  local path = opts.path
  local term = opts.term

  if term ~= "*" and not term:find("*") then
    term = "*" .. term .. "*"
  end

  local args = {}
  local function append(...)
    for _, v in ipairs({ ... }) do
      table.insert(args, v)
    end
  end

  if cmd == "fd" or cmd == "fdfind" then
    if filters.show_hidden then
      append("--hidden")
    end
    if not filters.respect_gitignore then
      append("--no-ignore")
    end
    append("--glob", term, path)
    append("--color", "never")
    if fd_supports_max_results then
      append("--max-results", limit)
    end
  elseif cmd == "find" then
    append(path)
    append("-type", "f,d")
    if not filters.show_hidden then
      append("-not", "-path", "*/.*")
    end
    append("-iname", term)
  elseif cmd == "where" then
    append("/r", path, term)
  else
    return { "No search command found!" }
  end

  Job
    :new({
      command = cmd,
      args = args,
      enable_recording = false,
      maximum_results = limit or 100,
      on_stdout = function(err, line)
        if opts.on_insert then
          opts.on_insert(err, line)
        end
      end,
      on_stderr = function(err, line)
        if opts.on_insert then
          if not err then
            err = line
          end
          opts.on_insert(err, line)
        end
      end,
      on_exit = function(j, return_val)
        if opts.on_exit then
          opts.on_exit(return_val)
        end
      end,
    })
    :start()
end

return M
