local utils = require("neo-tree.utils")
local globtopattern = require("neo-tree.sources.filesystem.lib.globtopattern")
local log = require("neo-tree.log")

-- File nesting a la JetBrains (#117).
local M = {}

---@alias neotree.FileNesting.Callback fun(item: table, siblings: table[], rule: neotree.FileNesting.Rule): neotree.FileNesting.Matches

---@class neotree.FileNesting.Matcher
---@field rules table<string, neotree.FileNesting.Rule>|neotree.FileNesting.Rule[]
---@field get_children neotree.FileNesting.Callback
---@field get_nesting_callback fun(item: table): neotree.FileNesting.Callback|nil A callback that returns all the files

local DEFAULT_PATTERN_PRIORITY = 100
---@class neotree.FileNesting.Rule
---@field priority number? Default is 100. Higher is prioritized.
---@field _priority number The internal priority, lower is prioritized. Determined through priority and the key for the rule at setup.

---@class neotree.FileNesting.Rule.Pattern : neotree.FileNesting.Rule
---@field files string[]
---@field files_exact string[]?
---@field files_glob string[]?
---@field ignore_case boolean? Default is false
---@field pattern string

---@class neotree.FileNesting.Matcher.Pattern : neotree.FileNesting.Matcher
---@field rules neotree.FileNesting.Rule.Pattern[]
local pattern_matcher = {
  rules = {},
}

---@class neotree.FileNesting.Rule.Extension : neotree.FileNesting.Rule
---@field [integer] string

---@class neotree.FileNesting.Matcher.Extension : neotree.FileNesting.Matcher
---@field rules table<string, neotree.FileNesting.Rule.Extension>
local extension_matcher = {
  rules = {},
}

local matchers = {
  pattern = pattern_matcher,
  exts = extension_matcher,
}

---@class neotree.FileNesting.Matches
---@field priority number
---@field parent table
---@field children table[]

extension_matcher.get_nesting_callback = function(item)
  local rule = extension_matcher.rules[item.exts]
  if utils.truthy(rule) then
    return function(inner_item, siblings)
      return {
        parent = inner_item,
        children = extension_matcher.get_children(inner_item, siblings, rule),
        priority = rule._priority,
      }
    end
  end
  return nil
end

---@type neotree.FileNesting.Callback
extension_matcher.get_children = function(item, siblings, rule)
  local matching_files = {}
  if siblings == nil then
    return matching_files
  end
  for _, ext in pairs(rule) do
    for _, sibling in pairs(siblings) do
      if
        sibling.id ~= item.id
        and sibling.exts == ext
        and item.base .. "." .. ext == sibling.name
      then
        table.insert(matching_files, sibling)
      end
    end
  end
  ---@type neotree.FileNesting.Matches
  return matching_files
end

pattern_matcher.get_nesting_callback = function(item)
  ---@type neotree.FileNesting.Rule.Pattern[]
  local matching_rules = {}
  for _, rule in ipairs(pattern_matcher.rules) do
    if item.name:match(rule.pattern) then
      table.insert(matching_rules, rule)
    end
  end

  if #matching_rules > 0 then
    return function(inner_item, siblings)
      local match_set = {}
      ---@type neotree.FileNesting.Matches[]
      local all_item_matches = {}
      for _, rule in ipairs(matching_rules) do
        ---@type neotree.FileNesting.Matches
        local item_matches = {
          priority = rule._priority,
          parent = inner_item,
          children = {},
        }
        local matched_siblings = pattern_matcher.get_children(inner_item, siblings, rule)
        for _, match in ipairs(matched_siblings) do
          -- Use file path as key to prevent duplicates
          if not match_set[match.id] then
            match_set[match.id] = true
            table.insert(item_matches.children, match)
          end
        end
        table.insert(all_item_matches, item_matches)
      end

      return all_item_matches
    end
  end
  return nil
end

local pattern_matcher_types = {
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

---@type neotree.FileNesting.Callback
pattern_matcher.get_children = function(item, siblings, rule)
  local matching_files = {}
  if siblings == nil then
    return matching_files
  end

  for type, type_functions in pairs(pattern_matcher_types) do
    for _, pattern in pairs(rule[type] or {}) do
      repeat
        ---@cast rule neotree.FileNesting.Rule.Pattern
        local item_name = rule.ignore_case and item.name:lower() or item.name

        local success, replaced_pattern = pcall(string.gsub, item_name, rule.pattern, pattern)
        if not success then
          log.error("Error using file glob '" .. pattern .. "'; Error: " .. replaced_pattern)
          break
        end
        for _, sibling in pairs(siblings) do
          if sibling.id ~= item.id then
            local sibling_name = rule.ignore_case and sibling.name:lower() or sibling.name
            local glob_or_file = type_functions.get_pattern(replaced_pattern)
            if type_functions.match(sibling_name, glob_or_file) then
              table.insert(matching_files, sibling)
            end
          end
        end
      until true
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
  ---@type neotree.FileNesting.Matches[]
  local nesting_relationships = {}
  for _, parent in pairs(context.nesting) do
    local siblings = context.folders[parent.parent_path].children
    vim.list_extend(nesting_relationships, parent.nesting_callback(parent, siblings))
  end

  table.sort(nesting_relationships, function(a, b)
    if a.priority == b.priority then
      return a.parent.id < b.parent.id
    end
    return a.priority < b.priority
  end)

  -- Then apply them in order
  for _, relationship in ipairs(nesting_relationships) do
    local folder = context.folders[relationship.parent.parent_path]
    for _, sibling in ipairs(relationship.children) do
      if not sibling.is_nested then
        table.insert(relationship.parent.children, sibling)
        sibling.is_nested = true
        sibling.nesting_parent = relationship.parent

        if folder ~= nil then
          for index, file_to_check in ipairs(folder.children) do
            if file_to_check.id == sibling.id then
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
  local cbs = {}
  for _, matcher in ipairs(enabled_matchers) do
    local callback = matcher.get_nesting_callback(item)
    if callback ~= nil then
      table.insert(cbs, callback)
    end
  end
  if #cbs <= 1 then
    return cbs[1]
  else
    return function(...)
      local res = {}
      for _, cb in ipairs(cbs) do
        vim.list_extend(res, cb(...))
      end
      return res
    end
  end
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
  config = config or {}
  enabled_matchers = {}
  local real_priority = 0
  for _, m in pairs(matchers) do
    m.rules = {}
  end

  for key, rule in
    utils.spairs(config, function(a, b)
      -- Organize by priority (descending) or by key (ascending)
      local a_prio = config[a].priority or DEFAULT_PATTERN_PRIORITY
      local b_prio = config[b].priority or DEFAULT_PATTERN_PRIORITY
      if a_prio == b_prio then
        return a < b
      end
      return a_prio > b_prio
    end)
  do
    rule.priority = rule.priority or DEFAULT_PATTERN_PRIORITY
    rule._priority = real_priority
    real_priority = real_priority + 1
    if rule.pattern then
      ---@cast rule neotree.FileNesting.Rule.Pattern
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
      -- priority does matter for pattern.rules
      table.insert(matchers.pattern.rules, rule)
    else
      ---@cast rule neotree.FileNesting.Rule.Extension
      matchers.exts.rules[key] = rule
    end
  end

  enabled_matchers = vim.tbl_filter(function(m)
    return not vim.tbl_isempty(m.rules)
  end, matchers)
end

return M
