local vim = vim

local M = {}

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
      print("Error parsing git status for: " .. line)
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
    status = status:sub(#status, #status) -- only working tree status
    local parts = M.split(absolute_path, M.path_separator)
    M.reduce(parts, "", function (acc, part)
      local new_path = acc .. M.path_separator .. part
      local path_status = git_status[new_path]
      if not path_status then
        git_status[new_path] = status
      elseif path_status ~= "M" then
        -- Prioritze M then A over all others
        if status == "M" then
         git_status[new_path] = "M"
        elseif status:match("[ACR]") then
         git_status[new_path] = "A"
        elseif path_status == "!" then
          git_status[new_path] = "!"
        else
          git_status[new_path] = status
        end
      end
      return new_path
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
---@return table table The value at the path or the default value.
M.get_value = function(sourceObject, valuePath, defaultValue)
    local value = defaultValue or {}
    if sourceObject == nil then
        return value
    end
    local pathParts = M.split(valuePath, ".")
    local currentTable = sourceObject
    for _, part in ipairs(pathParts) do
        if currentTable[part] ~= nil then
            currentTable = currentTable[part]
        else
            return value
        end
    end
    return currentTable or value
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

---The file system path separator for the current platform.
M.path_separator = "/"
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win32unix') == 1
if is_windows == true then
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

---Merges overrideTable into baseTable. This mutates baseTable.
---@param base_table table The base table that provides default values.
---@param override_table table The table to override the base table with.
---@return table table The merged table.
local table_merge_internal = function(base_table, override_table)
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

return M
