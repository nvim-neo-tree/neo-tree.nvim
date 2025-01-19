local utils = require("neo-tree.utils")
local Path = require("plenary.path")
local globtopattern = require("neo-tree.sources.filesystem.lib.globtopattern")
local log = require("neo-tree.log")

-- File nesting a la JetBrains (#117).
local M = {}

---@alias neotree.FileNesting.Callback fun(item: table, siblings: table[]): table[]

---@class neotree.FileNesting.Matcher
---@field enabled boolean
---@field config table<string, any>
---@field get_children neotree.FileNesting.Callback
---@field get_nesting_callback fun(item: table): neotree.FileNesting.Callback|nil

---@class neotree.FileNesting.Pattern.Rule
---@field files string[]
---@field files_exact string[]
---@field files_glob string[]
---@field ignore_case boolean Default is false
---@field pattern string

---@class neotree.FileNesting.PatternMatcher : neotree.FileNesting.Matcher
---@field config table<string, neotree.FileNesting.Pattern.Rule>
local pattern_matcher = {
  enabled = false,
  config = {},
}

---@class neotree.FileNesting.Extension.Rule

---@class neotree.FileNesting.ExtensionMatcher : neotree.FileNesting.Matcher
---@field config table<string, neotree.FileNesting.Extension.Rule>
local extension_matcher = {
  enabled = false,
  config = {},
}

---@alias neotree.FileNesting.Matchers table<string, neotree.FileNesting.Matcher>
local matchers = {
  pattern = pattern_matcher,
  exts = extension_matcher,
}

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
  ---@type neotree.FileNesting.Pattern.Rule[]
  local matching_rules = {}
  for _, rule_config in pairs(pattern_matcher.config) do
    if item.name:match(rule_config.pattern) then
      table.insert(matching_rules, rule_config)
    end
  end

  if #matching_rules > 0 then
    return function(inner_item, siblings)
      local all_matching_files = {}
      for _, rule_config in ipairs(matching_rules) do
        local matches = pattern_matcher.get_children(inner_item, siblings, rule_config)
        for _, match in ipairs(matches) do
          -- Use file path as key to prevent duplicates
          all_matching_files[match.id] = match
        end
      end

      -- Convert table to array
      local result = {}
      for _, file in pairs(all_matching_files) do
        table.insert(result, file)
      end
      return result
    end
  end
  return nil
end

pattern_matcher.types = {
  files_glob = {
    get_pattern = function(pattern)
      return globtopattern.globtopattern(pattern)
    end,
    match = function(filename, pattern)
      return filename:match(pattern)
    end,
  },
  files_exact = {
    get_pattern = function(pattern)
      return pattern
    end,
    match = function(filename, pattern)
      return filename == pattern
    end,
  },
}

---@param item any
---@param siblings any
---@param rule neotree.FileNesting.Pattern.Rule
pattern_matcher.get_children = function(item, siblings, rule)
  local matching_files = {}
  if siblings == nil then
    return matching_files
  end

  for type, type_functions in pairs(pattern_matcher.types) do
    for _, pattern in pairs(rule[type] or {}) do
      local item_name = item.name
      if rule.ignore_case ~= nil and item.name_lcase ~= nil then
        item_name = item.name_lcase
      end

      local success, replaced_pattern = pcall(string.gsub, item_name, rule.pattern, pattern)
      if not success then
        log.error("Error using file glob '" .. pattern .. "'; Error: " .. replaced_pattern)
        goto continue
      end
      local glob_or_file = type_functions.get_pattern(replaced_pattern)
      for _, sibling in pairs(siblings) do
        if
          sibling.id ~= item.id
          and sibling.is_nested ~= true
          and item.parent_path == sibling.parent_path
        then
          local sibling_name = sibling.name
          if rule.ignore_case ~= nil and sibling.name_lcase ~= nil then
            sibling_name = sibling.name_lcase
          end
          if type_functions.match(sibling_name, glob_or_file) then
            table.insert(matching_files, sibling)
          end
        end
      end
      ::continue::
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
  return pos ~= nil
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

function M.nest_items(context)
  if M.is_enabled() == false or vim.tbl_isempty(context.nesting or {}) then
    return
  end

  -- First collect all nesting relationships
  local all_nesting_relationships = {}
  for _, config in pairs(context.nesting) do
    local files = config.nesting_callback(config, context.all_items)
    if files and #files > 0 then
      table.insert(all_nesting_relationships, {
        parent = config,
        children = files,
      })
    end
  end

  -- Then apply them in order
  for _, relationship in ipairs(all_nesting_relationships) do
    local folder = context.folders[relationship.parent.parent_path]
    for _, to_be_nested in ipairs(relationship.children) do
      if not to_be_nested.is_nested then
        table.insert(relationship.parent.children, to_be_nested)
        to_be_nested.is_nested = true
        to_be_nested.nesting_parent = relationship.parent

        if folder ~= nil then
          for index, file_to_check in ipairs(folder.children) do
            if file_to_check.id == to_be_nested.id then
              table.remove(folder.children, index)
              break
            end
          end
        end
      end
    end
  end
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

---@alias neotree.FileNesting.Rule neotree.FileNesting.Extension.Rule | neotree.FileNesting.Pattern.Rule
---@alias neotree.Config.FileNesting table<string, neotree.FileNesting.Rule>

---Setup the module with the given config
---@param config neotree.Config.FileNesting
function M.setup(config)
  for key, matcher in pairs(config or {}) do
    if matcher.pattern ~= nil then
      ---@cast matcher neotree.FileNesting.Pattern.Rule
      if matcher.ignore_case == true then
        matcher.pattern = case_insensitive_pattern(matcher.pattern)
      end
      matcher.files_glob = {}
      matcher.files_exact = {}
      for _, glob in pairs(matcher.files) do
        if matcher.ignore_case == true then
          glob = glob:lower()
        end
        local replaced = glob:gsub("%%%d+", "")
        if is_glob(replaced) then
          table.insert(matcher.files_glob, glob)
        else
          table.insert(matcher.files_exact, glob)
        end
      end
      matchers.pattern.config[key] = matcher
    else
      ---@cast matcher neotree.FileNesting.Extension.Rule
      matchers.exts.config[key] = matcher
    end
  end
  local next = next
  for _, value in pairs(matchers) do
    if next(value.config) ~= nil then
      value.enabled = true
    end
  end
end

return M
