local vim = vim
local log = require("neo-tree.log")
local filesize = require("neo-tree.utils.filesize.filesize")
local bit = require("bit")
local ffi_available, ffi = pcall(require, "ffi")

local FILE_ATTRIBUTE_HIDDEN = 0x2

if ffi_available then
  ffi.cdef([[
  int GetFileAttributesA(const char *path);
  ]])
end

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
---@enum NeotreeDebounceStrategy
M.debounce_strategy = {
  CALL_FIRST_AND_LAST = 0,
  CALL_LAST_ONLY = 1,
}

---@enum NeotreeDebounceAction
M.debounce_action = {
  START_NORMAL = 0,
  START_ASYNC_JOB = 1,
  COMPLETE_ASYNC_JOB = 2,
}

---Part of debounce. Moved out of the function to eliminate memory leaks.
---@param id string Identifier for the debounce group, such as the function name.
---@param frequency_in_ms number Miniumum amount of time between invocations of fn.
---@param strategy NeotreeDebounceStrategy The debounce_strategy to use, determines which calls to fn are not dropped.
---@param action NeotreeDebounceAction? The debounce_action to use, determines how the function is invoked
local function defer_function(id, frequency_in_ms, strategy, action)
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
---@param strategy NeotreeDebounceStrategy The debounce_strategy to use, determines which calls to fn are not dropped.
---@param action NeotreeDebounceAction? The debounce_action to use, determines how the function is invoked
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
  fn = nil
  fn_data.fn = fn

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

--- Returns true if the contents of two tables are equal.
M.tbl_equals = function(table1, table2)
  -- same object
  if table1 == table2 then
    return true
  end

  -- not the same type
  if type(table1) ~= "table" or type(table2) ~= "table" then
    return false
  end

  -- If tables are lists, check if they have the same values in the same order
  if #table1 ~= #table2 then
    return false
  end
  for i, v in ipairs(table1) do
    if table2[i] ~= v then
      return false
    end
  end

  -- Check if the tables have the same key/value pairs
  for k, v in pairs(table1) do
    if table2[k] ~= v then
      return false
    end
  end
  for k, v in pairs(table2) do
    if table1[k] ~= v then
      return false
    end
  end

  -- No differences found, tables are equal
  return true
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

---Converts a filesize from libuv.stats into a human readable string with appropriate units.
---@param size any
---@return string
M.human_size = function(size)
  local human = filesize(size, { output = "string" })
  ---@cast human string
  return human
end

---Gets non-zero diagnostics counts for each open file and each ancestor directory.
---severity_number and severity_string refer to the highest severity with
---non-zero diagnostics count.
---Entry is nil if all counts are 0
---@return table table
---{ [file_path] = {
---    severity_number = int,
---    severity_string = string,
---    Error = int or nil,
---    Warn = int or nil,
---    Info = int or nil
---    Hint = int or nil,
---  } or nil }
M.get_diagnostic_counts = function()
  local lookup = {}

  for ns, _ in pairs(vim.diagnostic.get_namespaces()) do
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local success, file_name = pcall(vim.api.nvim_buf_get_name, bufnr)
      if success then
        -- TODO: remove is_disabled check when dropping support for 0.8
        local enabled
        if vim.diagnostic.is_enabled then
          enabled = vim.diagnostic.is_enabled({ bufnr = bufnr, ns_id = ns })
        elseif vim.diagnostic.is_disabled then
          enabled = not vim.diagnostic.is_disabled(bufnr, ns)
        else
          enabled = true
        end

        if enabled then
          for severity, _ in ipairs(vim.diagnostic.severity) do
            local diagnostics = vim.diagnostic.get(bufnr, { namespace = ns, severity = severity })

            if #diagnostics > 0 then
              local severity_string = diag_severity_to_string(severity)
              -- Get or create the entry for this file
              local entry = lookup[file_name]
              if entry == nil then
                entry = {
                  severity_number = severity,
                  severity_string = severity_string,
                }
                lookup[file_name] = entry
              end
              -- Set the count for this diagnostic type
              if severity_string ~= nil then
                entry[severity_string] = #diagnostics
              end

              -- Set the overall severity to the most severe so far
              -- Error = 1, Warn = 2, Info = 3, Hint = 4
              if severity < entry.severity_number then
                entry.severity_number = severity
                entry.severity_string = severity_string
              end
            end
          end
        end
      end
    end
  end

  for file_name, file_entry in pairs(lookup) do
    -- Now bubble this status up to the parent directories
    local parts = M.split(file_name, M.path_separator)
    table.remove(parts) -- pop the last part so we don't override the file's status
    M.reduce(parts, "", function(acc, part)
      local path = (M.is_windows and acc == "") and part or M.path_join(acc, part)

      if file_entry.severity_number then
        if not lookup[path] then
          lookup[path] = {
            severity_number = file_entry.severity_number,
            severity_string = file_entry.severity_string,
          }
        else -- lookup[path].severity_number ~= nil
          local min_severity = math.min(lookup[path].severity_number, file_entry.severity_number)
          lookup[path].severity_number = min_severity
          lookup[path].severity_string = diag_severity_to_string(min_severity)
        end
      end

      return path
    end)
  end
  return lookup
end

--- DEPRECATED: This will be removed in v3. Use `get_opened_buffers` instead.
---Gets a lookup of all open buffers keyed by path with the modifed flag as the value
---@return table opened_buffers { [buffer_name] = bool }
M.get_modified_buffers = function()
  local opened_buffers = M.get_opened_buffers()
  for bufname, bufinfo in pairs(opened_buffers) do
    opened_buffers[bufname] = bufinfo.modified
  end
  return opened_buffers
end

---Gets a lookup of all open buffers keyed by path with additional information
---@return table opened_buffers { [buffer_name] = { modified = bool } }
M.get_opened_buffers = function()
  local opened_buffers = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.buflisted(buffer) ~= 0 then
      local buffer_name = vim.api.nvim_buf_get_name(buffer)
      if buffer_name == nil or buffer_name == "" then
        buffer_name = "[No Name]#" .. buffer
      end
      opened_buffers[buffer_name] = {
        ["modified"] = vim.api.nvim_buf_get_option(buffer, "modified"),
        ["loaded"] = vim.api.nvim_buf_is_loaded(buffer),
      }
    end
  end
  return opened_buffers
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

local stat_providers = {
  default = function(node)
    return vim.loop.fs_stat(node.path)
  end,
}

--- Gets the statics for a node in the file system. The `stat` object will be cached
--- for the lifetime of the node.
---
---@param node table The Nui TreeNode node to get the stats for.
---@return StatTable | table
---
---@class StatTime
--- @field sec number
---
---@class StatTable
--- @field birthtime StatTime
--- @field mtime StatTime
--- @field size number
M.get_stat = function(node)
  if node.stat == nil then
    local provider = stat_providers[node.stat_provider or "default"]
    local success, stat = pcall(provider, node)
    node.stat = success and stat or {}
  end
  return node.stat
end

---Register a function to provide stats for a node.
---@param name string The name of the stat provider.
---@param func function The function to call to get the stats.
M.register_stat_provider = function(name, func)
  stat_providers[name] = func
  log.debug("Registered stat provider", name)
end

---Handles null coalescing into a table at any depth.
---@param sourceObject table The table to get a vlue from.
---@param valuePath string The path to the value to get.
---@param defaultValue any|nil The default value to return if the value is nil.
---@param strict_type_check boolean? Whether to require the type of the value is
---the same as the default value.
---@return any value The value at the path or the default value.
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
      if type(currentTable[part]) ~= "table" then
        currentTable[part] = {}
      end
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

---Determines if a file should be filtered by a given list of glob patterns.
---@param pattern_list table The list of glob patterns to filter by.
---@param path string The full path to the file.
---@param name string|nil The name of the file.
---@return boolean
M.is_filtered_by_pattern = function(pattern_list, path, name)
  if pattern_list == nil then
    return false
  end
  if name == nil then
    _, name = M.split_path(path)
  end
  for _, p in ipairs(pattern_list) do
    local separator_pattern = M.is_windows and "\\" or "/"
    local filename = string.find(p, separator_pattern) and path or name
    if string.find(filename, p) then
      return true
    end
  end
  return false
end

M.is_floating = function(win_id)
  win_id = win_id or vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(win_id)
  if cfg.relative > "" or cfg.external then
    return true
  end
  return false
end

M.is_winfixbuf = function(win_id)
  if vim.fn.exists("&winfixbuf") == 1 then
    win_id = win_id or vim.api.nvim_get_current_win()
    return vim.api.nvim_get_option_value("winfixbuf", { win = win_id })
  end
  return false
end

---Evaluates the value of <afile>, which comes from an autocmd event, and determines if it
---is a valid file or some sort of utility buffer like quickfix or neo-tree itself.
---@param afile string The path or relative path to the file.
---@param true_for_terminals boolean? Whether to return true for terminals, normally it would be false.
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

M.get_appropriate_window = function(state, ignore_winfixbuf)
  -- Avoid triggering autocommands when switching windows
  local eventignore = vim.o.eventignore
  vim.o.eventignore = "all"

  local current_window = vim.api.nvim_get_current_win()

  -- use last window if possible
  local suitable_window_found = false
  local nt = require("neo-tree")
  local ignore_ft = nt.config.open_files_do_not_replace_types
  local ignore = M.list_to_dict(ignore_ft)
  ignore["neo-tree"] = true
  if nt.config.open_files_in_last_window then
    local prior_window = nt.get_prior_window(ignore, ignore_winfixbuf)
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
  while attempts < 5 and not suitable_window_found do
    local bt = vim.bo.buftype or "normal"
    if ignore[vim.bo.filetype] or ignore[bt] or M.is_floating() then
      attempts = attempts + 1
      vim.cmd("wincmd w")
    elseif ignore_winfixbuf and M.is_winfixbuf() then
      attempts = attempts + 1
      vim.cmd("wincmd w")
    else
      suitable_window_found = true
    end
  end
  if not suitable_window_found then
    -- go back to the neotree window, this will forve it to open a new split
    vim.api.nvim_set_current_win(current_window)
  end

  local winid = vim.api.nvim_get_current_win()
  local is_neo_tree_window = vim.bo.filetype == "neo-tree"
  vim.api.nvim_set_current_win(current_window)

  vim.o.eventignore = eventignore

  return winid, is_neo_tree_window
end

---Resolves the width to a number
---@param width number|string|function
M.resolve_width = function(width)
  local default_width = 40
  local available_width = vim.o.columns
  if type(width) == "string" then
    if string.sub(width, -1) == "%" then
      width = tonumber(string.sub(width, 1, #width - 1)) / 100
      width = width * available_width
    else
      width = tonumber(width)
    end
  elseif type(width) == "function" then
    width = width()
  end

  if type(width) ~= "number" then
    width = default_width
  end

  return math.floor(width)
end

M.force_new_split = function(current_position, escaped_path)
  local result, err
  local split_command = "vsplit"
  -- respect window position in user config when Neo-tree is the only window
  if current_position == "left" then
    split_command = "rightbelow vs"
  elseif current_position == "right" then
    split_command = "leftabove vs"
  end
  if escaped_path == M.escape_path_for_cmd("[No Name]") then
    -- vim's default behavior is to overwrite [No Name] buffers.
    -- We need to split first and then open the path to workaround this behavior.
    result, err = pcall(vim.cmd, split_command)
    if result then
      vim.cmd.edit(escaped_path)
    end
  else
    result, err = pcall(vim.cmd, split_command .. " " .. escaped_path)
  end
  return result, err
end

---Open file in the appropriate window.
---@param state table The state of the source
---@param path string The file to open
---@param open_cmd string? The vimcommand to use to open the file
---@param bufnr number|nil The buffer number to open
M.open_file = function(state, path, open_cmd, bufnr)
  open_cmd = open_cmd or "edit"
  -- If the file is already open, switch to it.
  bufnr = bufnr or M.find_buffer_by_name(path)
  if bufnr <= 0 then
    bufnr = nil
  else
    local buf_cmd_lookup =
      { edit = "b", e = "b", split = "sb", sp = "sb", vsplit = "vert sb", vs = "vert sb" }
    local cmd_for_buf = buf_cmd_lookup[open_cmd]
    if cmd_for_buf then
      open_cmd = cmd_for_buf
    else
      bufnr = nil
    end
  end

  if M.truthy(path) then
    local escaped_path = M.escape_path_for_cmd(path)
    local bufnr_or_path = bufnr or escaped_path
    local events = require("neo-tree.events")
    local result = true
    local err = nil
    local event_result = events.fire_event(events.FILE_OPEN_REQUESTED, {
      state = state,
      path = path,
      open_cmd = open_cmd,
      bufnr = bufnr,
    }) or {}
    if event_result.handled then
      events.fire_event(events.FILE_OPENED, path)
      return
    end
    if state.current_position == "current" then
      result, err = pcall(vim.cmd, open_cmd .. " " .. bufnr_or_path)
    else
      local winid, is_neo_tree_window = M.get_appropriate_window(state)
      vim.api.nvim_set_current_win(winid)
      -- TODO: make this configurable, see issue #43
      if is_neo_tree_window then
        local width = vim.api.nvim_win_get_width(0)
        if width == vim.o.columns then
          -- Neo-tree must be the only window, restore it's status as a sidebar
          width = M.get_value(state, "window.width", 40, false)
          width = M.resolve_width(width)
        end
        result, err = M.force_new_split(state.current_position, escaped_path)
        vim.api.nvim_win_set_width(winid, width)
      else
        result, err = pcall(vim.cmd, open_cmd .. " " .. bufnr_or_path)
      end
    end
    if not result and string.find(err or "", "winfixbuf") and M.is_winfixbuf() then
      local winid, is_neo_tree_window = M.get_appropriate_window(state, true)
      -- Rescan window list to find a window that is not winfixbuf.
      -- If found, retry executing command in that window,
      -- otherwise, all windows are either neo-tree or winfixbuf so we make a new split.
      if not is_neo_tree_window and not M.is_winfixbuf(winid) then
        vim.api.nvim_set_current_win(winid)
        result, err = pcall(vim.cmd, open_cmd .. " " .. bufnr_or_path)
      else
        result, err = M.force_new_split(state.current_position, escaped_path)
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
    -- Turn mixed forward and back slashes into all forward slashes
    -- using NeoVim's logic
    path = vim.fs.normalize(path)
    -- Now use backslashes, as expected by the rest of Neo-Tree's code
    path = path:gsub("/", M.path_separator)
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

---Escapes a path primarily relying on `vim.fn.fnameescape`. This function should
---only be used when preparing a path to be used in a vim command, such as `:e`.
---
---For Windows systems, this function handles punctuation characters that will
---be escaped, but may appear at the beginning of a path segment. For example,
---the path `C:\foo\(bar)\baz.txt` (where foo, (bar), and baz.txt are segments)
---will remain unchanged when escaped by `fnaemescape` on a Windows system.
---However, if that string is used to edit a file with `:e`, `:b`, etc., the open
---parenthesis will be treated as an escaped character and the path separator will
---be lost.
---
---For more details, see issue #889 when this function was introduced, and further
---discussions in #1264, #1352, and #1448.
---@param path string
---@return string
M.escape_path_for_cmd = function(path)
  local escaped_path = vim.fn.fnameescape(path)
  if M.is_windows then
    -- there is too much history to this logic to capture in a reasonable comment.
    -- essentially, the following logic adds a number of `\` depending on the leading
    -- character in a path segment. see #1264, #1352, and #1448 for more info.
    local need_extra_esc = path:find("[%[%]`%$~]")
    local esc = need_extra_esc and "\\\\" or "\\"
    escaped_path = escaped_path:gsub("\\[%(%)%^&;]", esc .. "%1")
    if need_extra_esc then
      escaped_path = escaped_path:gsub("\\\\['` ]", "\\%1")
    end
  end
  return escaped_path
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
  if ffi_available and M.is_windows then
    return bit.band(ffi.C.GetFileAttributesA(path), FILE_ATTRIBUTE_HIDDEN) ~= 0
  else
    return false
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

---Splits string by sep on first occurrence. brace_expand_split("a,b,c", ",") -> { "a", "b,c" }. nil if separator not found.
---@param s string: input string
---@param separator string: separator
---@return string, string | nil
local brace_expand_split = function(s, separator)
  local pos = 1
  local depth = 0
  while pos <= s:len() do
    local c = s:sub(pos, pos)
    if c == "\\" then
      pos = pos + 1
    elseif c == separator and depth == 0 then
      return s:sub(1, pos - 1), s:sub(pos + 1)
    elseif c == "{" then
      depth = depth + 1
    elseif c == "}" then
      if depth > 0 then
        depth = depth - 1
      end
    end
    pos = pos + 1
  end
  return s, nil
end

---Perform brace expansion on a string and return the sequence of the results
---@param s string?: input string which is inside braces, if nil return { "" }
---@return string[] | nil: list of strings each representing the individual expanded strings
local brace_expand_contents = function(s)
  if s == nil then -- no closing brace "}"
    return { "" }
  elseif s == "" then -- brace with no content "{}"
    return { "{}" }
  end

  ---Generate a sequence from from..to..step and apply `func`
  ---@param from string | number: initial value
  ---@param to string | number: end value
  ---@param step string | number: step value
  ---@param func fun(i: number): string | nil function(string | number) -> string | nil: function applied to all values in sequence. if return is nil, the value will be ignored.
  ---@return string[]: generated string list
  ---@private
  local function resolve_sequence(from, to, step, func)
    local f, t = tonumber(from), tonumber(to)
    local st = (t < f and -1 or 1) * math.abs(tonumber(step) or 1) -- reverse (negative) step if t < f
    ---@type string[]
    local items = {}
    for i = f, t, st do
      local r = func(i)
      if r ~= nil then
        table.insert(items, r)
      end
    end
    return items
  end

  ---If pattern matches the input string `s`, apply an expansion by `resolve_func`
  ---@param pattern string: regex to match on `s`
  ---@param resolve_func fun(from: string, to: string, step: string): string[]
  ---@return string[] | nil: expanded sequence or nil if failed
  local function try_sequence_on_pattern(pattern, resolve_func)
    local from, to, step = string.match(s, pattern)
    if from then
      return resolve_func(from, to, step)
    end
    return nil
  end

  ---Process numeric sequence expression. e.g. {0..2} -> {0,1,2}, {01..05..2} -> {01,03,05}
  local resolve_sequence_num = function(from, to, step)
    local format = "%d"
    -- Pad strings in the presence of a leading zero
    local pattern = "^-?0%d"
    if from:match(pattern) or to:match(pattern) then
      format = "%0" .. math.max(#from, #to) .. "d"
    end
    return resolve_sequence(from, to, step, function(i)
      return string.format(format, i)
    end)
  end

  ---Process alphabet sequence expression. e.g. {a..c} -> {a,b,c}, {a..e..2} -> {a,c,e}
  local resolve_sequence_char = function(from, to, step)
    return resolve_sequence(from:byte(), to:byte(), step, function(i)
      return i ~= 92 and string.char(i) or nil -- 92 == '\\' is ignored in bash
    end)
  end

  local check_list = {
    { [=[^(-?%d+)%.%.(-?%d+)%.%.(-?%d+)$]=], resolve_sequence_num },
    { [=[^(-?%d+)%.%.(-?%d+)$]=], resolve_sequence_num },
    { [=[^(%a)%.%.(%a)%.%.(-?%d+)$]=], resolve_sequence_char },
    { [=[^(%a)%.%.(%a)$]=], resolve_sequence_char },
  }
  for _, list in ipairs(check_list) do
    local regex, func = table.unpack(list)
    local sequence = try_sequence_on_pattern(regex, func)
    if sequence then
      return sequence
    end
  end

  -- Regular `,` separated expression. x{a,b,c} -> {xa,xb,xc}
  local items, tmp_s = {}, nil
  tmp_s = s
  while tmp_s ~= nil do
    items[#items + 1], tmp_s = brace_expand_split(tmp_s, ",")
  end
  if #items == 1 then -- Only one expansion found. Abort.
    return nil
  end
  return vim.tbl_flatten(items)
end

---brace_expand:
-- Perform a BASH style brace expansion to generate arbitrary strings.
-- Especially useful for specifying structured file / dir names.
-- USAGE:
--   - `require("neo-tree.utils").brace_expand("x{a..e..2}")` -> `{ "xa", "xc", "xe" }`
--   - `require("neo-tree.utils").brace_expand("file.txt{,.bak}")` -> `{ "file.txt", "file.txt.bak" }`
--   - `require("neo-tree.utils").brace_expand("./{a,b}/{00..02}.lua")` -> `{ "./a/00.lua", "./a/01.lua", "./a/02.lua", "./b/00.lua", "./b/01.lua", "./b/02.lua" }`
-- More examples for BASH style brace expansion can be found here: https://facelessuser.github.io/bracex/
---@param s string: input string. e.g. {a..e..2} -> {a,c,e}, {00..05..2} -> {00,03,05}
---@return string[]: result of expansion, array with at least one string (one means it failed to expand and the raw string is returned)
M.brace_expand = function(s)
  local preamble, postamble = brace_expand_split(s, "{")
  if postamble == nil then
    return { s }
  end

  local expr, postscript, contents = nil, nil, nil
  postscript = postamble
  while contents == nil do
    local old_expr = expr
    expr, postscript = brace_expand_split(postscript, "}")
    if old_expr then
      expr = old_expr .. "}" .. expr
    end
    if postscript == nil then -- No closing brace found, so we put back the unmatched '{'
      preamble = preamble .. "{"
      expr, postscript = nil, postamble
    end
    contents = brace_expand_contents(expr)
  end

  -- Concat everything. Pass postscript recursively.
  ---@type string[]
  local result = {}
  for _, item in ipairs(contents) do
    for _, suffix in ipairs(M.brace_expand(postscript)) do
      result[#result + 1] = table.concat({ preamble, item, suffix })
    end
  end
  return result
end

---Indexes a table that uses paths as keys. Case-insensitive logic is used when
---running on Windows.
---
---Consideration should be taken before using this function, because it is a
---bit expensive on Windows. However, this function helps when trying to index
---with absolute path keys, which can have inconsistent casing on Windows (such
---as with drive letters).
---@param tbl table
---@param key string
---@return unknown
M.index_by_path = function(tbl, key)
  local value = tbl[key]
  if value ~= nil then
    return value
  end

  -- on windows, paths that differ only by case are considered equal
  -- TODO: we should optimize this, see discussion in #1353
  if M.is_windows then
    local key_lower = key:lower()
    for k, v in pairs(tbl) do
      if key_lower == k:lower() then
        return v
      end
    end
  end

  return value
end

return M
