local vim = vim

local M = {}

local get_find_command = function(state)
  if state.find_command then
    return state.find_command
  end

  if 1 == vim.fn.executable "fd" then
    state.find_command = "fd"
  elseif 1 == vim.fn.executable "fdfind" then
    state.find_command = "fdfind"
  elseif 1 == vim.fn.executable "find" and vim.fn.has "win32" == 0 then
    state.find_command = "find"
  elseif 1 == vim.fn.executable "where" then
    state.find_command = "where"
  end
  return state.find_command
end

M.find_files = function(opts, term, limit)
  local filters = opts.filters
  local cmd = get_find_command(opts)
  local path = '"' .. opts.path .. '"'
  if term:find("*") then
    term = '"' .. term .. '"'
  else
    term = '"*' .. term .. '*"'
  end

  local find_command = { cmd }
  local function append(str)
    table.insert(find_command, str)
  end
  if cmd == "fd" or cmd == "fdfind" then
    find_command = { cmd, "--glob" }
    append("--glob")
    if filters.show_hidden then
      append("--hidden")
    end
    if not filters.respect_gitignore then
      append("--no-ignore")
    end
    append(term)
    append(path)
  elseif cmd == "find" then
    append(path)
    append("-type f,d")
    if not filters.show_hidden then
      append('-not -path "*/.*"')
    end
    append("-iname")
    append(term)
  elseif cmd == "where" then
    append("/r")
    append(path)
    append(term)
  else
    return { "No search command found!" }
  end

  if limit then
    append(" | head -" .. limit)
  end

  local find_command_str = table.concat(find_command, " ")
  return vim.fn.systemlist(find_command_str)

end

return M
