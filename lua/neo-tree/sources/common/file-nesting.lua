local utils = require("neo-tree.utils")
local Path = require("plenary.path")
local globtopattern = require("neo-tree.sources.filesystem.lib.globtopattern")
local log = require("neo-tree.log")

-- File nesting a la JetBrains (#117).
local M = {}

---@alias neotree.FileNesting.Callback fun(item: table, siblings: table[]): table[]

---@class neotree.FileNesting.Matcher
---@field config table<string, any>
---@field get_children neotree.FileNesting.Callback
---@field get_nesting_callback fun(item: table): neotree.FileNesting.Callback|nil A callback that returns all the files

---@class neotree.FileNesting.Rule

---@class neotree.FileNesting.PatternMatcher.Rule : neotree.FileNesting.Rule
---@field files string[]
---@field files_exact string[]
---@field files_glob string[]
---@field ignore_case boolean Default is false
---@field pattern string

---@class neotree.FileNesting.PatternMatcher : neotree.FileNesting.Matcher
---@field config table<string, neotree.FileNesting.PatternMatcher.Rule>
local pattern_matcher = {
  config = {},
}

---@class neotree.FileNesting.ExtensionMatcher.Rule : neotree.FileNesting.Rule

---@class neotree.FileNesting.ExtensionMatcher : neotree.FileNesting.Matcher
---@field config table<string, neotree.FileNesting.ExtensionMatcher.Rule>
local extension_matcher = {
  config = {},
}

---@class neotree.FileNesting.Matches
---@field pattern neotree.FileNesting.PatternMatcher
---@field exts neotree.FileNesting.ExtensionMatcher
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
  ---@type neotree.FileNesting.PatternMatcher.Rule[]
  local matching_rules = {}
  for _, rule_config in pairs(pattern_matcher.config) do
    if item.name:match(rule_config.pattern) then
      table.insert(matching_rules, rule_config)
    end
  end

  if #matching_rules > 0 then
    return function(inner_item, siblings)
      local all_matching_files = {}
      for _, rule in ipairs(matching_rules) do
        local matches = pattern_matcher.get_children(inner_item, siblings, rule)
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
---@param rule neotree.FileNesting.PatternMatcher.Rule
---@return table children The children of the patterns
pattern_matcher.get_children = function(item, siblings, rule)
  local matching_files = {}
  if siblings == nil then
    return matching_files
  end

  for type, type_functions in pairs(pattern_matcher.types) do
    for _, pattern in pairs(rule[type] or {}) do
      local item_name = rule.ignore_case and item.name_lcase or item.name

      local success, replaced_pattern = pcall(string.gsub, item_name, rule.pattern, pattern)
      if not success then
        log.error("Error using file glob '" .. pattern .. "'; Error: " .. replaced_pattern)
        goto continue
      end
      for _, sibling in pairs(siblings) do
        if
          sibling.id ~= item.id
          and sibling.is_nested ~= true
          and item.parent_path == sibling.parent_path
        then
          local sibling_name = rule.ignore_case and sibling.name_lcase or sibling.name
          local glob_or_file = type_functions.get_pattern(replaced_pattern)
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

---@type neotree.FileNesting.Matcher[]
local enabled_matchers = {}

function M.is_enabled()
  return not vim.tbl_isempty(enabled_matchers)
end

function M.nest_items(context)
  if not M.is_enabled() or vim.tbl_isempty(context.nesting or {}) then
    return
  end

  -- First collect all nesting relationships
  local all_nesting_relationships = {}
  for _, parent in pairs(context.nesting) do
    local files = parent.nesting_callback(parent, context.all_items)
    if files and #files > 0 then
      table.insert(all_nesting_relationships, {
        parent = parent,
        children = files,
      })
    end
  end

  -- Then apply thems in order
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
  for _, matcher in pairs(enabled_matchers) do
    local callback = matcher.get_nesting_callback(item)
    if callback ~= nil then
      return callback
    end
  end
  return nil
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

---Setup the module with the given config
---@param config table<string, neotree.FileNesting.Rule>
function M.setup(config)
  for _, m in pairs(matchers) do
    m.config = {}
  end
  for key, rule in pairs(config or {}) do
    if rule.pattern ~= nil then
      ---@cast rule neotree.FileNesting.PatternMatcher.Rule
      rule.ignore_case = rule.ignore_case or false
      if rule.ignore_case then
        rule.pattern = case_insensitive_pattern(rule.pattern)
      end
      rule.files_glob = {}
      rule.files_exact = {}
      for _, glob in pairs(rule.files) do
        if rule.ignore_case then
          glob = glob:lower()
        end
        local replaced = glob:gsub("%%%d+", "")
        if is_glob(replaced) then
          table.insert(rule.files_glob, glob)
        else
          table.insert(rule.files_exact, glob)
        end
      end
      matchers.pattern.config[key] = rule
    else
      ---@cast rule neotree.FileNesting.ExtensionMatcher.Rule
      matchers.exts.config[key] = rule
    end
  end
  enabled_matchers = vim.tbl_filter(function(matcher)
    return not vim.tbl_isempty(matcher.config)
  end, matchers)
end

return M
