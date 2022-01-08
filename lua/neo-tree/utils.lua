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
    while len> 0 do
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
M.get_git_status = function ()
  local project_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  local git_output = vim.fn.systemlist("git status --porcelain")
  local git_status = {}
  local codes = "[ACDMRTU!%?%s]"
  codes = codes .. codes


  for _, line in ipairs(git_output) do
    local status = line:match("^(" .. codes .. ")%s")
    local relative_path = line:match("^" .. codes .. '%s+(.+)$')
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

    -- Now bubble this status up to the parent directories
    local parts = M.split(absolute_path, M.path_separator)
    table.remove(parts) -- pop the last part so we don't override the file's status
    M.reduce(parts, "", function (acc, part)
      local path = acc .. M.path_separator .. part
      local path_status = git_status[path]
      local file_status = get_simple_git_status_code(status)
      git_status[path] = get_priority_git_status_code(path_status, file_status)
      return path
    end)
  end

  return git_status
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
    for k,v in pairs(tbl) do
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
    print(config_option .. ": " .. vim.inspect(opt))
    if type(opt) == "function" then
       local success,val = pcall(opt, state)
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
M.is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win32unix') == 1
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
  string.gsub(inputString, pattern, function(c) fields[#fields + 1] = c end)

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
  if M.path_separator == '/' then
    parentPath = '/' .. parentPath
  end
  return parentPath, name
end

local table_merge_internal
---Merges overrideTable into baseTable. This mutates baseTable.
---@param base_table table The base table that provides default values.
---@param override_table table The table to override the base table with.
---@return table table The merged table.
table_merge_internal = function(base_table, override_table)
    for k,v in pairs(override_table) do
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
M.table_copy = function (source_table)
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
