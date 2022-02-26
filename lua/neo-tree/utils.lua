local vim = vim
local log = require("neo-tree.log")
-- Backwards compatibility
table.pack = table.pack or function(...)
  return { n = select("#", ...), ... }
end
table.unpack = table.unpack or unpack

local M = {}

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
M.debounce_strategy = {
  CALL_FIRST_AND_LAST = 0,
  CALL_LAST_ONLY = 1,
}

M.debounce_action = {
  START_NORMAL = 0,
  START_ASYNC_JOB = 1,
  COMPLETE_ASYNC_JOB = 2,
}

---Call fn, but not more than once every x milliseconds.
---@param id string Identifier for the debounce group, such as the function name.
---@param fn function Function to be executed.
---@param frequency_in_ms number Miniumum amount of time between invocations of fn.
---@param strategy number The debounce_strategy to use, determines which calls to fn are not dropped.
M.debounce = function(id, fn, frequency_in_ms, strategy, action)
  local fn_data = tracked_functions[id]

  local defer_function
  defer_function = function()
    fn_data.in_debounce_period = true
    vim.defer_fn(function()
      local current_data = tracked_functions[id]
      if not current_data then
        return
      end
      if fn_data.async_in_progress then
        defer_function()
        return
      end
      local _fn = current_data.fn
      current_data.fn = nil
      current_data.in_debounce_period = false
      if _fn ~= nil then
        M.debounce(id, _fn, current_data.frequency_in_ms, strategy, action)
      end
    end, frequency_in_ms)
  end

  if fn_data == nil then
    if action == M.debounce_action.COMPLETE_ASYNC_JOB then
      -- original call complete and no further requests have been made
      return
    end
    -- first call for this id
    fn_data = {
      id = id,
      in_debounce_period = false,
      fn = fn,
      frequency_in_ms = frequency_in_ms,
    }
    tracked_functions[id] = fn_data
    if strategy == M.debounce_strategy.CALL_LAST_ONLY then
      defer_function()
      return
    end
  else
    fn_data.fn = fn
    fn_data.frequency_in_ms = frequency_in_ms
    if action == M.debounce_action.COMPLETE_ASYNC_JOB then
      fn_data.async_in_progress = false
      return
    elseif fn_data.async_in_progress then
      defer_function()
      return
    end
  end

  if fn_data.in_debounce_period then
    -- This id was called recently and can't be executed again yet.
    -- Last one in wins.
    return
  end

  -- Run the requested function normally.
  -- Use a pcall to ensure the debounce period is still respected even if
  -- this call throws an error.
  local success, result = true, nil
  fn_data.in_debounce_period = true
  if type(fn) == "function" then
    success, result = pcall(fn)
  end
  fn_data.fn = nil
  fn = nil

  if not success then
    log.error("debounce ", id, " error: ", result)
  elseif result and action == M.debounce_action.START_ASYNC_JOB then
    -- This can't fire again until the COMPLETE_ASYNC_JOB signal is sent.
    fn_data.async_in_progress = true
  end

  if strategy == M.debounce_strategy.CALL_LAST_ONLY then
    if fn_data.async_in_progress then
      defer_function()
    else
      -- We are done with this debounce
      tracked_functions[id] = nil
    end
  else
    -- Now schedule the next earliest execution.
    -- If there are no calls to run the same function between now
    -- and when this deferred executes, nothing will happen.
    -- If there are several calls, only the last one in will run.
    strategy = M.debounce_strategy.CALL_LAST_ONLY
    defer_function()
  end
end

M.execute_command = function(cmd)
  local result = vim.fn.systemlist(cmd)

  -- An empty result is ok
  if vim.v.shell_error ~= 0 or (#result > 0 and vim.startswith(result[1], "fatal:")) then
    return false, {}
  else
    return true, result
  end
end

M.find_buffer_by_name = function(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_name = vim.api.nvim_buf_get_name(buf)
    if buf_name == name then
      return buf
    end
  end
  return -1
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

M.is_floating = function(win_id)
  win_id = win_id or vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(win_id)
  if cfg.relative > "" or cfg.external then
    return true
  end
  return false
end

M.map = function(tbl, fn)
  local t = {}
  for k, v in pairs(tbl) do
    t[k] = fn(v)
  end
  return t
end

---Open file in the appropriate window.
---@param state table The state of the source
---@param path string The file to open
---@param open_cmd string The vimcommand to use to open the file
M.open_file = function(state, path, open_cmd)
  open_cmd = open_cmd or "edit"
  if open_cmd == "edit" then
    -- If the file is already open, switch to it.
    local bufnr = M.find_buffer_by_name(path)
    if bufnr > 0 then
      open_cmd = "b"
    end
  end

  if M.truthy(path) then
    local events = require("neo-tree.events")
    local event_result = events.fire_event(events.FILE_OPEN_REQUESTED, {
      state = state,
      path = path,
      open_cmd = open_cmd,
    }) or {}
    if event_result.handled then
      events.fire_event(events.FILE_OPENED, path)
      return
    end
    if state.current_position == "split" then
      vim.cmd(open_cmd .. " " .. path)
    else
      -- use last window if possible
      local suitable_window_found = false
      local nt = require("neo-tree")
      if nt.config.open_files_in_last_window then
        local prior_window = nt.get_prior_window()
        if prior_window > 0 then
          local success = pcall(vim.api.nvim_set_current_win, prior_window)
          if success then
            suitable_window_found = true
          end
        end
      end
      -- find a suitable window to open the file in
      if not suitable_window_found then
        if state.current_position == "right" then
          vim.cmd("wincmd t")
        else
          vim.cmd("wincmd w")
        end
      end
      local attempts = 0
      while attempts < 4 and vim.bo.filetype == "neo-tree" do
        attempts = attempts + 1
        vim.cmd("wincmd w")
      end
      -- TODO: make this configurable, see issue #43
      if vim.bo.filetype == "neo-tree" then
        -- Neo-tree must be the only window, restore it's status as a sidebar
        local winid = vim.api.nvim_get_current_win()
        local width = M.get_value(state, "window.width", 40)
        vim.cmd("vsplit " .. path)
        vim.api.nvim_win_set_width(winid, width)
      else
        vim.cmd(open_cmd .. " " .. path)
      end
    end
    events.fire_event(events.FILE_OPENED, path)
  end
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
      log.error("Error resolving config option: " .. config_option .. ": " .. val)
      return default_value
    end
  else
    return opt
  end
end

---Normalize a path, to avoid errors when comparing paths.
---@param path string The path to be normalize.
---@return string string The normalized path.
M.normalize_path = function(path)
  if M.is_windows then
    -- normalize the drive letter to uppercase
    path = path:sub(1, 1):upper() .. path:sub(2)
  end
  return path
end

---Check if a path is a subpath of another.
--@param base string The base path.
--@param path string The path to check is a subpath.
--@return boolean boolean True if it is a subpath, false otherwise.
M.is_subpath = function(base, path)
  if not M.truthy(base) or not M.truthy(path) then
    return false
  elseif base == path then
    return true
  end
  base = M.normalize_path(base)
  path = M.normalize_path(path)
  return string.sub(path, 1, string.len(base)) == base
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

---Joins arbitrary number of paths together.
---@param ... string The paths to join.
---@return string
M.path_join = function(...)
  local args = { ... }
  if #args == 0 then
    return ""
  end

  local all_parts = {}
  if type(args[1]) == "string" and args[1]:sub(1, 1) == M.path_separator then
    all_parts[1] = ""
  end

  for _, arg in ipairs(args) do
    local arg_parts = M.split(arg, M.path_separator)
    vim.list_extend(all_parts, arg_parts)
  end
  return table.concat(all_parts, M.path_separator)
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

---Evaluate the truthiness of a value, according to js/python rules.
---@param value any
---@return boolean
M.truthy = function(value)
  if value == nil then
    return false
  end
  if type(value) == "boolean" then
    return value
  end
  if type(value) == "string" then
    return value > ""
  end
  if type(value) == "number" then
    return value > 0
  end
  if type(value) == "table" then
    return #value > 0
  end
  return true
end

M.windowize_path = function(path)
  return path:gsub("/", "\\")
end

M.wrap = function(func, ...)
  if type(func) ~= "function" then
    error("Expected function, got " .. type(func))
  end
  local wrapped_args = { ... }
  return function(...)
    local all_args = table.pack(table.unpack(wrapped_args), ...)
    func(table.unpack(all_args))
  end
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
