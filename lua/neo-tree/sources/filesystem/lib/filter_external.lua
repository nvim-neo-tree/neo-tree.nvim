local vim = vim
local Job = require("plenary.job")

local M = {}

local get_find_command = function(state)
  if state.find_command then
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
    append("--max-results", limit)
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
