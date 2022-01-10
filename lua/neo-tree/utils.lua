local vim = vim

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

local diag_severity_to_string = function(severity)
  if severity == vim.diagnostic.severity.ERROR then
    return "Error"
  elseif severity == vim.diagnostic.severity.WARN then
    return "Warning"
  elseif severity == vim.diagnostic.severity.INFO then
    return "Information"
  elseif severity == vim.diagnostic.severity.HINT then
    return "Hint"
  else
    return nil
  end
end

local tracked_functions = {}

---Call fn, but not more than once every x milliseconds.
---@param id string Identifier for the debounce group, such as the function name.
---@param fn function Function to be executed.
---@param frequency_in_ms number Miniumum amount of time between invocations of fn.
---@param callback function Called with the result of executing fn as: callback(success, result)
M.debounce = function(id, fn, frequency_in_ms, callback)
  local fn_data = tracked_functions[id]
  if fn_data == nil then
    -- first call for this id
    fn_data = {
      id = id,
      fn = nil,
      frequency_in_ms = frequency_in_ms,
      postponed_callback = nil,
      in_debounce_period = true,
    }
    tracked_functions[id] = fn_data
  else
    if fn_data.in_debounce_period then
      -- This id was called recently and can't be executed again yet.
      -- Just keep track of the details for this request so it
      -- can be executed at the end of the debounce period.
      -- Last one in wins.
      fn_data.fn = fn
      fn_data.frequency_in_ms = frequency_in_ms
      fn_data.postponed_callback = callback
      return
    end
  end

  -- Run the requested function normally.
  -- Use a pcall to ensure the debounce period is still respected even if
  -- this call throws an error.
  fn_data.in_debounce_period = true
  local success, result = pcall(fn)

  if not success then
    print("Error in neo-tree.utils.debounce: ", result)
  end

  -- Now schedule the next earliest execution.
  -- If there are no calls to run the same function between now
  -- and when this deferred executes, nothing will happen.
  -- If there are several calls, only the last one in will run.
  vim.defer_fn(function()
    local current_data = tracked_functions[id]
    local _callback = current_data.postponed_callback
    local _fn = current_data.fn
    current_data.postponed_callback = nil
    current_data.fn = nil
    current_data.in_debounce_period = false
    if _fn ~= nil then
      M.debounce(id, _fn, current_data.frequency_in_ms, _callback)
    end
  end, frequency_in_ms)

  -- The callback function is outside the scope of the debounce period
  if type(callback) == "function" then
    callback(success, result)
  end
end

---Gets diagnostic severity counts for all files
---@return table table { file_path = { Error = int, Warning = int, Information = int, Hint = int, Unknown = int } }
M.get_diagnostic_counts = function()
  local d = vim.diagnostic.get()
  local lookup = {}
  for _, diag in ipairs(d) do
    if diag.source == "Lua Diagnostics." and diag.message == "Undefined global `vim`." then
      -- ignore this diagnostic
    else
      local success, file_name = pcall(vim.api.nvim_buf_get_name, diag.bufnr)
      if success then
        local sev = diag_severity_to_string(diag.severity)
        if sev then
          local entry = lookup[file_name] or { severity_number = 4 }
          entry[sev] = (entry[sev] or 0) + 1
          entry.severity_number = math.min(entry.severity_number, diag.severity)
          entry.severity_string = diag_severity_to_string(entry.severity_number)
          lookup[file_name] = entry
        end
      end
    end
  end

  for file_name, entry in pairs(lookup) do
    -- Now bubble this status up to the parent directories
    local parts = M.split(file_name, M.path_separator)
    table.remove(parts) -- pop the last part so we don't override the file's status
    M.reduce(parts, "", function(acc, part)
      local path = acc .. M.path_separator .. part
      local path_entry = lookup[path] or { severity_number = 4 }
      path_entry.severity_number = math.min(path_entry.severity_number, entry.severity_number)
      path_entry.severity_string = diag_severity_to_string(path_entry.severity_number)
      lookup[path] = path_entry
      return path
    end)
  end
  return lookup
end

M.get_git_project_root = function()
  return vim.fn.systemlist("git rev-parse --show-toplevel")[1]
end

---Parse "git status" output for the current working directory.
---@return table table Table with the path as key and the status as value.
M.get_git_status = function(exclude_directories)
  local project_root = M.get_git_project_root()
  local git_output = vim.fn.systemlist("git status --porcelain")
  local git_status = {}
  local codes = "[ACDMRTU!%?%s]"
  codes = codes .. codes

  for _, line in ipairs(git_output) do
    local status = line:match("^(" .. codes .. ")%s")
    local relative_path = line:match("^" .. codes .. "%s+(.+)$")
    if not relative_path then
      if line:match("fatal: not a git repository") then
        return {}
      else
        print("Error parsing git status for: " .. line)
      end
      break
    end
    local renamed = line:match("^" .. codes .. "%s+.*%s->%s(.*)$")
    if renamed then
      relative_path = renamed
    end
    if relative_path:sub(1, 1) == '"' then
      -- path was quoted, remove quoting
      relative_path = relative_path:match('^"(.+)".*')
    end
    local absolute_path = project_root .. M.path_separator .. relative_path
    git_status[absolute_path] = status

    if not exclude_directories then
      -- Now bubble this status up to the parent directories
      local parts = M.split(absolute_path, M.path_separator)
      table.remove(parts) -- pop the last part so we don't override the file's status
      M.reduce(parts, "", function(acc, part)
        local path = acc .. M.path_separator .. part
        local path_status = git_status[path]
        local file_status = get_simple_git_status_code(status)
        git_status[path] = get_priority_git_status_code(path_status, file_status)
        return path
      end)
    end
  end

  return git_status, project_root
end

---Resolves some variable to a string. The object can be either a string or a
--function that returns a string.
---@param functionOrString any The object to resolve.
---@param node table The current node, which is passed to the function if it is a function.
---@param state any The current state, which is passed to the function if it is a function.
---@return string string The resolved string.
M.getStringValue = function(functionOrString, node, state)
  if type(functionOrString) == "function" then
    return functionOrString(node, state)
  else
    return functionOrString
  end
end

---Handles null coalescing into a table at any depth.
---@param sourceObject table The table to get a vlue from.
---@param valuePath string The path to the value to get.
---@param defaultValue any The default value to return if the value is nil.
---@param strict_type_check boolean Whether to require the type of the value is
---the same as the default value.
---@return table table The value at the path or the default value.
M.get_value = function(sourceObject, valuePath, defaultValue, strict_type_check)
  if sourceObject == nil then
    return defaultValue
  end
  local pathParts = M.split(valuePath, ".")
  local currentTable = sourceObject
  for _, part in ipairs(pathParts) do
    if currentTable[part] == nil then
      return defaultValue
    else
      currentTable = currentTable[part]
    end
  end

  if currentTable ~= nil then
    return currentTable
  end
  if strict_type_check then
    if type(defaultValue) == type(currentTable) then
      return currentTable
    else
      return defaultValue
    end
  end
end

M.map = function(tbl, fn)
  local t = {}
  for k, v in pairs(tbl) do
    t[k] = fn(v)
  end
  return t
end

M.reduce = function(list, memo, func)
  for _, i in ipairs(list) do
    memo = func(memo, i)
  end
  return memo
end

M.resolve_config_option = function(state, config_option, default_value)
  local opt = M.get_value(state, config_option, default_value, false)
  if type(opt) == "function" then
    local success, val = pcall(opt, state)
    if success then
      return val
    else
      print("Error resolving config option: " .. config_option .. ": " .. val)
      return default_value
    end
  else
    return opt
  end
end
---The file system path separator for the current platform.
M.path_separator = "/"
M.is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win32unix") == 1
if M.is_windows == true then
  M.path_separator = "\\"
end

---Split string into a table of strings using a separator.
---@param inputString string The string to split.
---@param sep string The separator to use.
---@return table table A table of strings.
M.split = function(inputString, sep)
  local fields = {}

  local pattern = string.format("([^%s]+)", sep)
  local _ = string.gsub(inputString, pattern, function(c)
    fields[#fields + 1] = c
  end)

  return fields
end

---Split a path into a parentPath and a name.
---@param path string The path to split.
---@return table table parentPath, name
M.split_path = function(path)
  if not path then
    return nil, nil
  end
  if path == M.path_separator then
    return nil, M.path_separator
  end
  local parts = M.split(path, M.path_separator)
  local name = table.remove(parts)
  local parentPath = table.concat(parts, M.path_separator)
  if M.path_separator == "/" then
    parentPath = "/" .. parentPath
  end
  return parentPath, name
end

local table_merge_internal
---Merges overrideTable into baseTable. This mutates baseTable.
---@param base_table table The base table that provides default values.
---@param override_table table The table to override the base table with.
---@return table table The merged table.
table_merge_internal = function(base_table, override_table)
  for k, v in pairs(override_table) do
    if type(v) == "table" then
      if type(base_table[k] or false) == "table" then
        table_merge_internal(base_table[k] or {}, override_table[k] or {})
      else
        base_table[k] = v
      end
    else
      base_table[k] = v
    end
  end
  return base_table
end

---Creates a deep copy of a table.
---@param source_table table The table to copy.
---@return table table The copied table.
M.table_copy = function(source_table)
  return table_merge_internal({}, source_table)
end

---Returns a new table that is the result of a deep merge two tables.
---@param base_table table The base table that provides default values.
---@param override_table table The table to override the base table with.
---@return table table The merged table.
M.table_merge = function(base_table, override_table)
  local merged_table = table_merge_internal({}, base_table)
  return table_merge_internal(merged_table, override_table)
end

---Returns a new list that is the result of dedeuplicating a list.
---@param list table The list to deduplicate.
---@return table table The list of unique values.
M.unique = function(list)
  local seen = {}
  local result = {}
  for _, item in ipairs(list) do
    if not seen[item] then
      table.insert(result, item)
      seen[item] = true
    end
  end
  return result
end

return M
