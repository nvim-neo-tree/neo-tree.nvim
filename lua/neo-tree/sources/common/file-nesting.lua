local iter = require("plenary.iterators").iter
local utils = require("neo-tree.utils")
local Path = require("plenary.path")
local globtopattern = require("neo-tree.sources.filesystem.lib.globtopattern")

-- File nesting a la JetBrains (#117).
local M = {}

local pattern_matcher = {
  enabled = false,
  config = {},
}

local extension_matcher = {
  enabled = false,
  config = {},
}

local matchers = {}
matchers.pattern = pattern_matcher
matchers.exts = extension_matcher

extension_matcher.get_nesting_callback = function(item)
  if utils.truthy(extension_matcher.config[item.exts]) then
    return extension_matcher.get_children
  end
  return nil
end

extension_matcher.get_children = function(item, siblings)
  local matching_files = {}
  if siblings == nil then
    return matching_files
  end
  for _, ext in pairs(extension_matcher.config[item.exts]) do
    for _, sibling in pairs(siblings) do
      if
        sibling.id ~= item.id
        and sibling.is_nested ~= true
        and item.parent_path == sibling.parent_path
        and sibling.exts == ext
      then
        table.insert(matching_files, sibling)
      end
    end
  end
  return matching_files
end

extension_matcher.get_parent = function(item)
  for base_exts, nesting_exts in pairs(extension_matcher.config) do
    for _, exts in ipairs(nesting_exts) do
      if item.exts == exts then
        local parent_id = utils.path_join(item.parent_path, item.base) .. "." .. base_exts
        if Path:new(parent_id):exists() then
          return parent_id
        end
      end
    end
  end
  return nil
end

pattern_matcher.get_nesting_callback = function(item)
  for _, rule_config in pairs(pattern_matcher.config) do
    if item.name:match(rule_config["pattern"]) then
      return function(item, siblings)
        local rule_config_helper = rule_config
        return pattern_matcher.get_children(item, siblings, rule_config_helper)
      end
    end
  end
  return nil
end

pattern_matcher.get_children = function(item, siblings, rule_config)
  local matching_files = {}
  if siblings == nil then
    return matching_files
  end

  for _, pattern in pairs(rule_config["files"]) do
    local glob_pattern =
      globtopattern.globtopattern(item.name:gsub(rule_config["pattern"], pattern))
    for _, sibling in pairs(siblings) do
      if
        sibling.id ~= item.id
        and sibling.is_nested ~= true
        and item.parent_path == sibling.parent_path
      then
        local sibling_name = sibling.name
        if rule_config["ignore_case"] ~= nil and sibling.name_lcase ~= nil then
          sibling_name = sibling.name_lcase
        end
        if sibling_name:match(glob_pattern) then
          table.insert(matching_files, sibling)
        end
      end
    end
  end
  return matching_files
end

--- Checks if file-nesting module is enabled by config
---@return boolean
function M.is_enabled()
  for _, matcher in pairs(matchers) do
    if matcher.enabled then
      return true
    end
  end
  return false
end

local function case_insensitive_pattern(pattern)
  -- find an optional '%' (group 1) followed by any character (group 2)
  local p = pattern:gsub("(%%?)(.)", function(percent, letter)
    if percent ~= "" or not letter:match("%a") then
      -- if the '%' matched, or `letter` is not a letter, return "as is"
      return percent .. letter
    else
      -- else, return a case-insensitive character class of the matched letter
      return string.format("[%s%s]", letter:lower(), letter:upper())
    end
  end)

  return p
end

function table_is_empty(table_to_check)
  return table_to_check == nil or next(table_to_check) == nil
end

function M.nest_items(context)
  if M.is_enabled() == false or table_is_empty(context.nesting) then
    return
  end

  for _, config in pairs(context.nesting) do
    local files = config.nesting_callback(config, context.all_items)
    local folder = context.folders[config.parent_path]
    for _, to_be_nested in ipairs(files) do
      table.insert(config.children, to_be_nested)
      to_be_nested.is_nested = true
      if folder ~= nil then
        for index, file_to_check in ipairs(folder.children) do
          if file_to_check.id == to_be_nested.id then
            table.remove(folder.children, index)
          end
        end
      end
    end
  end
end

--- Returns `item` nesting parent path if exists
---@return string?
function get_parent(item, siblings)
  if item.type ~= "file" then
    return nil
  end
  for _, matcher in pairs(matchers) do
    if matcher.enabled then
      local parent = matcher.get_parent(item, siblings)
      if parent ~= nil then
        return parent
      end
    end
  end

  return nil
end

--- Checks if `item` have a valid nesting lookup
---@return boolean
function M.can_have_nesting(item)
  for _, matcher in pairs(matchers) do
    if matcher.enabled then
      if matcher.can_have_nesting(item) then
        return
      end
    end
  end

  return false
end

function M.get_nesting_callback(item)
  for _, matcher in pairs(matchers) do
    if matcher.enabled then
      local callback = matcher.get_nesting_callback(item)
      if callback ~= nil then
        return callback
      end
    end
  end
  return nil
end

---Setup the module with the given config
---@param config table
function M.setup(config)
  for key, value in pairs(config or {}) do
    local type = "exts"
    if value["pattern"] ~= nil then
      type = "pattern"
      if value["ignore_case"] == true then
        value["pattern"] = case_insensitive_pattern(value["pattern"])
      end
    end
    matchers[type]["config"][key] = value
  end
  local next = next
  for _, value in pairs(matchers) do
    if next(value.config) ~= nil then
      value.enabled = true
    end
  end
end

return M
