local vim = vim
local log = require("neo-tree.log")
local Job = require("plenary.job")
local utils = require("neo-tree.utils")

local M = {}
local fd_supports_max_results = nil
local unpack = unpack or table.unpack

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
  local full_path_words = opts.find_by_full_path_words
  local regex, glob = opts.term, opts.term

  if full_path_words then
    local words = utils.split(glob, " ")
    regex = ".*" .. table.concat(words, ".*") .. ".*"
  else
    if glob ~= "*" then
      if glob:sub(1) ~= "*" then
        glob = "*" .. glob
      end
      if glob:sub(-1) ~= "*" then
        glob = glob .. "*"
      end
    end
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
    if full_path_words then
      append("--full-path", regex)
    else
      append("--glob", glob)
    end
    append(path)
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
    if full_path_words then
      append("-regextype",  "sed", "-regex", regex)
    else
      append("-iname", glob)
    end
  elseif cmd == "fzf" then
    -- This does not work yet, there's some kind of issue with how fzf uses stdout
    error("fzf is not a supported find_command")
    append("--no-sort", "--no-expect", "--filter", opts.term) -- using the raw term without glob patterns
  elseif cmd == "where" then
    append("/r", path, glob)
  else
    return { "No search command found!" }
  end

  if opts.find_args then
    if type(opts.find_args) == "string" then
      append(opts.find_args)
    elseif type(opts.find_args) == "table" then
      append(unpack(opts.find_args))
    elseif type(opts.find_args) == "function" then
      args = opts.find_args(cmd, path, glob, args)
    end
  end

  local maximum_results = limit or 100
  if fd_supports_max_results then
    maximum_results = nil
  end
  local item_count = 0
  local over_limit = false
  Job
    :new({
      command = cmd,
      cwd = path,
      args = args,
      enable_recording = false,
      on_stdout = function(err, line)
        if not over_limit then
          if opts.on_insert then
            opts.on_insert(err, line)
          end
          item_count = item_count + 1
          over_limit = maximum_results and item_count > maximum_results
        end
      end,
      on_stderr = function(err, line)
        if not over_limit then
          if opts.on_insert then
            if not err then
              err = line
            end
            opts.on_insert(err, line)
          end
          item_count = item_count + 1
          over_limit = maximum_results and item_count > maximum_results
        end
      end,
      on_exit = function(_, return_val)
        if opts.on_exit then
          opts.on_exit(return_val)
        end
      end,
    })
    :start()
end

return M
