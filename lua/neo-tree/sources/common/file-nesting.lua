local utils = require("neo-tree.utils")
local Path = require("plenary.path")
local globtopattern = require("neo-tree.sources.filesystem.lib.globtopattern")
local log = require("neo-tree.log")

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
        and item.base .. "." .. ext == sibling.name
      then
        table.insert(matching_files, sibling)
      end
    end
  end
  return matching_files
end

pattern_matcher.get_nesting_callback = function(item)
  for _, rule_config in pairs(pattern_matcher.config) do
    if item.name:match(rule_config["pattern"]) then
      return function(inner_item, siblings)
        local rule_config_helper = rule_config
        return pattern_matcher.get_children(inner_item, siblings, rule_config_helper)
      end
    end
  end
  return nil
end

pattern_matcher.pattern_types = {}
pattern_matcher.pattern_types.files_glob = {}
pattern_matcher.pattern_types.files_glob.get_pattern = function(pattern)
  return globtopattern.globtopattern(pattern)
end
pattern_matcher.pattern_types.files_glob.match = function(filename, pattern)
  return filename:match(pattern)
end
pattern_matcher.pattern_types.files_exact = {}
pattern_matcher.pattern_types.files_exact.get_pattern = function(pattern)
  return pattern
end
pattern_matcher.pattern_types.files_exact.match = function(filename, pattern)
  return filename == pattern
end

pattern_matcher.get_children = function(item, siblings, rule_config)
  local matching_files = {}
  if siblings == nil then
    return matching_files
  end
  for type, type_functions in pairs(pattern_matcher.pattern_types) do
    for _, pattern in pairs(rule_config[type]) do
      local item_name = item.name
      if rule_config["ignore_case"] ~= nil and item.name_lcase ~= nil then
        item_name = item.name_lcase
      end
      local success, replaced_pattern =
        pcall(string.gsub, item_name, rule_config["pattern"], pattern)
      if success then
        local glob_or_file = type_functions.get_pattern(replaced_pattern)
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
            if type_functions.match(sibling_name, glob_or_file) then
              table.insert(matching_files, sibling)
            end
          end
        end
      else
        log.error("Error using file glob '" .. pattern .. "'; Error: " .. replaced_pattern)
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

local function is_glob(str)
  local test = str:gsub("\\[%*%?%[%]]", "")
  local pos, _ = test:find("*")
  if pos ~= nil then
    return true
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

function flatten_nesting(nesting_parents)
  for key, config in pairs(nesting_parents) do
    if config.is_nested ~= nil then
      local parent = config.nesting_parent
      -- count for emergency escape
      local count = 0
      while parent.nesting_parent ~= nil and count < 100 do
        parent = parent.nesting_parent
        count = count + 1
      end
      if parent ~= nil then
        for _, child in pairs(config.children) do
          child.nesting_parent = parent
          table.insert(parent.children, child)
        end
        config.children = nil
      end
    end
    nesting_parents[key] = nil
  end
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
      to_be_nested.nesting_parent = config
      if folder ~= nil then
        for index, file_to_check in ipairs(folder.children) do
          if file_to_check.id == to_be_nested.id then
            table.remove(folder.children, index)
          end
        end
      end
    end
  end

  flatten_nesting(context.nesting)
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
      value["files_glob"] = {}
      value["files_exact"] = {}
      for _, glob in pairs(value["files"]) do
        if value["ignore_case"] == true then
          glob = glob:lower()
        end
        local replaced = glob:gsub("%%%d+", "")
        if is_glob(replaced) then
          table.insert(value["files_glob"], glob)
        else
          table.insert(value["files_exact"], glob)
        end
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
