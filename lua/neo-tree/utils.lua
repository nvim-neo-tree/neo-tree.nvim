local vim = vim
local log = require("neo-tree.log")
local bit = require("bit")
local ffi = require("ffi")

local FILE_ATTRIBUTE_HIDDEN = 0x2

ffi.cdef([[
int GetFileAttributesA(const char *path);
]])

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
    return "Warn"
  elseif severity == vim.diagnostic.severity.INFO then
    return "Info"
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

local defer_function
-- Part of debounce. Moved out of the function to eliminate memory leaks.
defer_function = function(id, frequency_in_ms, strategy, action)
  tracked_functions[id].in_debounce_period = true
  vim.defer_fn(function()
    local current_data = tracked_functions[id]
    if not current_data then
      return
    end
    if current_data.async_in_progress then
      defer_function(id, frequency_in_ms, strategy, action)
      return
    end
    local _fn = current_data.fn
    current_data.fn = nil
    current_data.in_debounce_period = false
    if _fn ~= nil then
      M.debounce(id, _fn, frequency_in_ms, strategy, action)
    end
  end, frequency_in_ms)
end

---Call fn, but not more than once every x milliseconds.
---@param id string Identifier for the debounce group, such as the function name.
---@param fn function Function to be executed.
---@param frequency_in_ms number Miniumum amount of time between invocations of fn.
---@param strategy number The debounce_strategy to use, determines which calls to fn are not dropped.
M.debounce = function(id, fn, frequency_in_ms, strategy, action)
  local fn_data = tracked_functions[id]

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
      defer_function(id, frequency_in_ms, strategy, action)
      return
    end
  else
    fn_data.fn = fn
    fn_data.frequency_in_ms = frequency_in_ms
    if action == M.debounce_action.COMPLETE_ASYNC_JOB then
      fn_data.async_in_progress = false
      return
    elseif fn_data.async_in_progress then
      defer_function(id, frequency_in_ms, strategy, action)
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
      defer_function(id, frequency_in_ms, strategy, action)
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
    defer_function(id, frequency_in_ms, strategy, action)
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
      local path = (M.is_windows and acc == "") and part or M.path_join(acc, part)
      local path_entry = lookup[path] or { severity_number = 4 }
      path_entry.severity_number = math.min(path_entry.severity_number, entry.severity_number)
      path_entry.severity_string = diag_severity_to_string(path_entry.severity_number)
      lookup[path] = path_entry
      return path
    end)
  end
  return lookup
end

---Gets a lookup of all open buffers keyed by path with the modifed flag as the value
---@return table
M.get_modified_buffers = function()
  local modified_buffers = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    local buffer_name = vim.api.nvim_buf_get_name(buffer)
    modified_buffers[buffer_name] = vim.api.nvim_buf_get_option(buffer, "modified")
  end
  return modified_buffers
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

---Return the keys of a given table.
---@param tbl table The table to get the keys of.
---@param sorted boolean Whether to sort the keys.
---@return table table The keys of the table.
M.get_keys = function(tbl, sorted)
  local keys = {}
  for k, _ in pairs(tbl) do
    table.insert(keys, k)
  end
  if sorted then
    table.sort(keys)
  end
  return keys
end

---Gets the usable columns in a window, subtracting sign, fold, and line number columns.
---@param winid integer The window id to get the columns of.
---@return number
M.get_inner_win_width = function(winid)
  local info = vim.fn.getwininfo(winid)
  if info and info[1] then
    return info[1].width - info[1].textoff
  else
    log.error("Could not get window info for window", winid)
  end
end

---Handles null coalescing into a table at any depth.
---@param sourceObject table The table to get a vlue from.
---@param valuePath string The path to the value to get.
---@param defaultValue any The default value to return if the value is nil.
---@param strict_type_check boolean Whether to require the type of the value is
---the same as the default value.
---@return table|nil table The value at the path or the default value.
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

---Sets a value at a path in a table, creating any missing tables along the way.
---@param sourceObject table The table to set a value in.
---@param valuePath string The path to the value to set.
---@param value any The value to set.
M.set_value = function(sourceObject, valuePath, value)
  local pathParts = M.split(valuePath, ".")
  local currentTable = sourceObject
  for i, part in ipairs(pathParts) do
    if i == #pathParts then
      currentTable[part] = value
    else
      currentTable = currentTable[part]
    end
  end
end

---Groups an array of items by a key.
---@param array table The array to group.
---@param key string The key to group by.
---@return table table The grouped array where the keys are the unique values of the specified key.
M.group_by = function(array, key)
  local result = {}
  for _, item in ipairs(array) do
    local keyValue = item[key]
    local group = result[keyValue]
    if group == nil then
      group = {}
      result[keyValue] = group
    end
    table.insert(group, item)
  end
  return result
end

M.is_floating = function(win_id)
  win_id = win_id or vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(win_id)
  if cfg.relative > "" or cfg.external then
    return true
  end
  return false
end

---Evaluates the value of <afile>, which comes from an autocmd event, and determines if it
---is a valid file or some sort of utility buffer like quickfix or neo-tree itself.
---@param afile string The path or relative path to the file.
---@param true_for_terminals boolean Whether to return true for terminals, normally it would be false.
---@return boolean boolean Whether the buffer is a real file.
M.is_real_file = function(afile, true_for_terminals)
  if type(afile) ~= "string" or afile == "" or afile == "quickfix" then
    return false
  end

  local source = afile:match("^neo%-tree ([%l%-]+) %[%d+%]")
  if source then
    return false
  end

  local success, bufnr = pcall(vim.fn.bufnr, afile)
  if success and bufnr > 0 then
    local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")

    if true_for_terminals and buftype == "terminal" then
      return true
    end
    -- all other buftypes are not real files
    if M.truthy(buftype) then
      return false
    end
    return true
  else
    return false
  end
end

---Creates a new table from an array with the array items as keys. If a dict like
---table is passed in, those keys will be copied to a new table.
---@param tbl table The table to copy items from.
---@return table table A new dictionary style table.
M.list_to_dict = function(tbl)
  local dict = {}
  -- leave the existing keys
  for key, val in pairs(tbl) do
    dict[key] = val
  end
  -- and convert the number indexed items
  for _, item in ipairs(tbl) do
    dict[item] = true
  end
  return dict
end

M.map = function(tbl, fn)
  local t = {}
  for k, v in pairs(tbl) do
    t[k] = fn(v)
  end
  return t
end

M.get_appropriate_window = function(state)
  -- Avoid triggering autocommands when switching windows
  local eventignore = vim.o.eventignore
  vim.o.eventignore = "all"

  local current_window = vim.api.nvim_get_current_win()

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
  while attempts < 5 and vim.bo.filetype == "neo-tree" do
    attempts = attempts + 1
    vim.cmd("wincmd w")
  end

  local winid = vim.api.nvim_get_current_win()
  local is_neo_tree_window = vim.bo.filetype == "neo-tree"
  vim.api.nvim_set_current_win(current_window)

  vim.o.eventignore = eventignore

  return winid, is_neo_tree_window
end

---Open file in the appropriate window.
---@param state table The state of the source
---@param path string The file to open
---@param open_cmd string The vimcommand to use to open the file
M.open_file = function(state, path, open_cmd)
  open_cmd = open_cmd or "edit"
  if open_cmd == "edit" or open_cmd == "e" then
    -- If the file is already open, switch to it.
    local bufnr = M.find_buffer_by_name(path)
    if bufnr > 0 then
      open_cmd = "b"
    end
  end

  if M.truthy(path) then
    local escaped_path = vim.fn.fnameescape(path)
    local events = require("neo-tree.events")
    local result = true
    local err = nil
    local event_result = events.fire_event(events.FILE_OPEN_REQUESTED, {
      state = state,
      path = path,
      open_cmd = open_cmd,
    }) or {}
    if event_result.handled then
      events.fire_event(events.FILE_OPENED, path)
      return
    end
    if state.current_position == "current" then
      result, err = pcall(vim.cmd, open_cmd .. " " .. escaped_path)
    else
      local winid, is_neo_tree_window = M.get_appropriate_window(state)
      vim.api.nvim_set_current_win(winid)
      -- TODO: make this configurable, see issue #43
      if is_neo_tree_window then
        -- Neo-tree must be the only window, restore it's status as a sidebar
        local width = M.get_value(state, "window.width", 40, false)
        result, err = pcall(vim.cmd, "vsplit " .. escaped_path)
        vim.api.nvim_win_set_width(winid, width)
      else
        result, err = pcall(vim.cmd, open_cmd .. " " .. escaped_path)
      end
    end
    if result or err == "Vim(edit):E325: ATTENTION" then
      -- fixes #321
      vim.api.nvim_buf_set_option(0, "buflisted", true)
      events.fire_event(events.FILE_OPENED, path)
    else
      log.error("Error opening file:", err)
    end
  end
end

M.reduce = function(list, memo, func)
  for _, i in ipairs(list) do
    memo = func(memo, i)
  end
  return memo
end

M.reverse_list = function(list)
  local result = {}
  for i = #list, 1, -1 do
    table.insert(result, list[i])
  end
  return result
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

---Remove the path separator from the end of a path in a cross-platform way.
---@param path string The path to remove the separator from.
---@return string string The path without any trailing separator.
---@return number count The number of separators removed.
M.remove_trailing_slash = function(path)
  if M.is_windows then
    return path:gsub("\\$", "")
  else
    return path:gsub("/$", "")
  end
end

---Sorts a list of paths in the order they would appear in a tree.
---@param paths table The list of paths to sort.
---@return table table The sorted list of paths.
M.sort_by_tree_display = function(paths)
  -- first turn the paths into a true tree
  local nodes = {}
  local index = {}
  local function create_nodes(path)
    local node = index[path]
    if node then
      return node
    end
    local parent, name = M.split_path(path)
    node = {
      name = name,
      path = path,
      children = {},
    }
    index[path] = node
    if parent == nil then
      table.insert(nodes, node)
    else
      local parent_node = index[parent]
      if parent_node == nil then
        parent_node = create_nodes(parent)
      end
      table.insert(parent_node.children, node)
    end
    return node
  end

  for _, path in ipairs(paths) do
    create_nodes(path)
  end

  -- create a lookup of the original paths so that we don't return anything
  -- that isn't in the original list
  local original_paths = M.list_to_dict(paths)

  -- sort folders before files
  local sort_by_name = function(a, b)
    local a_isdir = #a.children > 0
    local b_isdir = #b.children > 0
    if a_isdir and not b_isdir then
      return true
    elseif not a_isdir and b_isdir then
      return false
    else
      return a.name < b.name
    end
  end

  -- now we can walk the tree in the order that it would be displayed on the screen
  local result = {}
  local function walk_tree(node)
    if original_paths[node.path] then
      table.insert(result, node.path)
      original_paths[node.path] = nil -- just to be sure we don't return it twice
    end
    table.sort(node.children, sort_by_name)
    for _, child in ipairs(node.children) do
      walk_tree(child)
    end
  end

  walk_tree({ children = nodes })
  return result
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
---@return string|nil parentPath
---@return string|nil name
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
  if M.is_windows then
    if #parts == 1 then
      parentPath = parentPath .. M.path_separator
    elseif parentPath == "" then
      return nil, name
    end
  else
    parentPath = M.path_separator .. parentPath
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
    if arg == "" and #all_parts == 0 and not M.is_windows then
      all_parts = { "" }
    else
      local arg_parts = M.split(arg, M.path_separator)
      vim.list_extend(all_parts, arg_parts)
    end
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
      if type(base_table[k]) == "table" then
        table_merge_internal(base_table[k], v)
      else
        base_table[k] = v
      end
    else
      base_table[k] = v
    end
  end
  return base_table
end

---DEPRECATED: Use vim.deepcopy(source_table, { noref = 1 }) instead.
M.table_copy = function(source_table)
  return vim.deepcopy(source_table, { noref = 1 })
end

---DEPRECATED: Use vim.tbl_deep_extend("force", base_table, source_table) instead.
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
    return #vim.tbl_values(value) > 0
  end
  return true
end

M.is_expandable = function(node)
  return node.type == "directory" or node:has_children()
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

---Checks if the given path is hidden using the Windows hidden file/directory logic
---@param path string
---@return boolean
function M.is_hidden(path)
  if not M.is_windows then
    return false
  end
  return bit.band(ffi.C.GetFileAttributesA(path), FILE_ATTRIBUTE_HIDDEN) ~= 0
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
