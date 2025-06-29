local utils = require("neo-tree.utils")

local M = {}

---@param key string
M.normalize_map_key = function(key)
  if key == nil then
    return nil
  end
  if key:match("^<[^>]+>$") then
    local parts = utils.split(key, "-")
    if #parts == 2 then
      local mod = parts[1]:lower()
      if mod == "<a" then
        mod = "<m"
      end
      local alpha = parts[2]
      if #alpha > 2 then
        alpha = alpha:lower()
      end
      key = string.format("%s-%s", mod, alpha)
      return key
    else
      key = key:lower()
      if key == "<backspace>" then
        return "<bs>"
      elseif key == "<enter>" then
        return "<cr>"
      elseif key == "<return>" then
        return "<cr>"
      end
    end
  end
  return key
end

---@class neotree.SimpleMappings
---@field [string] string|function?

---@class neotree.SimpleMappingsByMode
---@field [string] neotree.SimpleMappings?

---@class neotree.Mappings : neotree.SimpleMappings
---@field [integer] neotree.SimpleMappingsByMode?

---@param map neotree.Mappings
---@return neotree.Mappings new_map
M.normalize_mappings = function(map)
  local new_map = M.normalize_simple_mappings(map)
  ---@cast new_map neotree.Mappings
  for i, mappings_by_mode in ipairs(map) do
    new_map[i] = {}
    for mode, simple_mappings in pairs(mappings_by_mode) do
      ---@cast simple_mappings neotree.SimpleMappings
      new_map[i][mode] = M.normalize_simple_mappings(simple_mappings)
    end
  end
  return new_map
end

---@param map neotree.SimpleMappings
---@return neotree.SimpleMappings new_map
M.normalize_simple_mappings = function(map)
  local new_map = {}
  for key, value in pairs(map) do
    if type(key) == "string" then
      local normalized_key = M.normalize_map_key(key)
      if normalized_key ~= nil then
        new_map[normalized_key] = value
      end
    end
  end
  return new_map
end

return M
