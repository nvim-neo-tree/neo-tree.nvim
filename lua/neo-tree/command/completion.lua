local parser = require("neo-tree.command.parser")
local utils = require("neo-tree.utils")

local M = {
  show_key_value_completions = true,
}

---@param key_prefix string?
---@param base_path string
---@return string paths_string
local get_path_completions = function(key_prefix, base_path)
  key_prefix = key_prefix or ""
  local completions = {}
  local expanded = parser.resolve_path(base_path)
  local path_completions = vim.fn.glob(expanded .. "*", false, true)
  for _, completion in ipairs(path_completions) do
    if expanded ~= base_path then
      -- we need to recreate the relative path from the aboluste path
      -- first strip trailing slashes to normalize
      if expanded:sub(-1) == utils.path_separator then
        expanded = expanded:sub(1, -2)
      end
      if base_path:sub(-1) == utils.path_separator then
        base_path = base_path:sub(1, -2)
      end
      -- now put just the current completion onto the base_path being used
      completion = base_path .. string.sub(completion, #expanded + 1)
    end
    table.insert(completions, key_prefix .. completion)
  end

  return table.concat(completions, "\n")
end

---@param key_prefix string?
---@return string references_string
local get_ref_completions = function(key_prefix)
  key_prefix = key_prefix or ""
  local completions = { key_prefix .. "HEAD" }
  local ok, refs = utils.execute_command("git show-ref")
  if not ok then
    return ""
  end
  for _, ref in ipairs(refs) do
    local _, i = ref:find("refs%/%a+%/")
    if i then
      table.insert(completions, key_prefix .. ref:sub(i + 1))
    end
  end

  return table.concat(completions, "\n")
end

---@param argLead string
---@param cmdLine string
---@return string candidates_string
M.complete_args = function(argLead, cmdLine)
  local candidates = {}
  local existing = utils.split(cmdLine, " ")
  local parsed = parser.parse(existing, false)

  local eq = string.find(argLead, "=")
  if eq == nil then
    if M.show_key_value_completions then
      -- may be the start of a new key=value pair
      for _, key in ipairs(parser.list_args) do
        key = tostring(key)
        if key:find(argLead, 1, true) and not parsed[key] then
          table.insert(candidates, key .. "=")
        end
      end

      for _, key in ipairs(parser.path_args) do
        key = tostring(key)
        if key:find(argLead, 1, true) and not parsed[key] then
          table.insert(candidates, key .. "=./")
        end
      end

      for _, key in ipairs(parser.ref_args) do
        key = tostring(key)
        if key:find(argLead, 1, true) and not parsed[key] then
          table.insert(candidates, key .. "=")
        end
      end
    end
  else
    -- continuation of a key=value pair
    local key = string.sub(argLead, 1, eq - 1)
    local value = string.sub(argLead, eq + 1)
    local arg_type = parser.argtype_lookup[key]
    if arg_type == parser.argtypes.PATH then
      return get_path_completions(key .. "=", value)
    elseif arg_type == parser.argtypes.REF then
      return get_ref_completions(key .. "=")
    elseif arg_type == parser.argtypes.LIST then
      local valid_values = parser.arguments[key].values
      if valid_values and not (parsed[key] and #parsed[key] > 0) then
        for _, vv in ipairs(valid_values) do
          if vv:find(value, 1, true) then
            table.insert(candidates, key .. "=" .. vv)
          end
        end
      end
    end
  end

  -- may be a value without a key
  for value, key in pairs(parser.reverse_lookup) do
    value = tostring(value)
    local key_already_used = false
    if parser.argtype_lookup[key] == parser.argtypes.LIST then
      key_already_used = type(parsed[key]) ~= "nil"
    else
      key_already_used = type(parsed[value]) ~= "nil"
    end

    if not key_already_used and value:find(argLead, 1, true) then
      table.insert(candidates, value)
    end
  end

  if #candidates == 0 then
    -- default to path completion
    return get_path_completions(nil, argLead) .. "\n" .. get_ref_completions(nil)
  end
  return table.concat(candidates, "\n")
end

return M
