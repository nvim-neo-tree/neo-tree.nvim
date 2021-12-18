local M = {}

---The file system path separator for the current platform.
M.pathSeparator = "/"
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win32unix') == 1
if is_windows == true then
  M.pathSeparator = "\\"
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

---Handles null coalescing into a table at any depth.
---@param sourceObject table The table to get a vlue from.
---@param valuePath string The path to the value to get.
---@param defaultValue any The default value to return if the value is nil.
---@return table table The value at the path or the default value.
M.getValue = function(sourceObject, valuePath, defaultValue)
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

---Merges overrideTable into baseTable. This mutates baseTable.
---@param baseTable table The base table that provides default values.
---@param overrideTable table The table to override the base table with.
---@return table table The merged table.
local tableMergeInternal = function(baseTable, overrideTable)
    for k,v in pairs(overrideTable) do
        if type(v) == "table" then
            if type(baseTable[k] or false) == "table" then
                tableMerge(baseTable[k] or {}, overrideTable[k] or {})
            else
                baseTable[k] = v
            end
        else
            baseTable[k] = v
        end
    end
    return baseTable
end

---Creates a deep copy of a table.
---@param sourceTable table The table to copy.
---@return table table The copied table.
M.tableCopy = function (sourceTable)
    return tableMergeInternal({}, sourceTable)
end

---Returns a new table that is the result of a deep merge two tables.
---@param baseTable table The base table that provides default values.
---@param overrideTable table The table to override the base table with.
---@return table table The merged table.
M.tableMerge = function(baseTable, overrideTable)
    local mergedTable = tableMergeInternal({}, baseTable)
    return tableMergeInternal(mergedTable, overrideTable)
end

return M
