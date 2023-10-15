local iter = require("plenary.iterators").iter
local utils = require("neo-tree.utils")
local Path = require("plenary.path")
local globtopattern = require("neo-tree.sources.filesystem.lib.globtopattern")

-- File nesting a la JetBrains (#117).
local M = {}
M.config = {}

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

extension_matcher.can_have_nesting = function(item)
  return utils.truthy(extension_matcher.config[item.exts])
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

pattern_matcher.can_have_nesting = function(item)
  for _, patternFiles in pairs(pattern_matcher.config) do
    if item.name:match(patternFiles["pattern"]) then
      return true
    end
  end
  return false
end

pattern_matcher.get_parent = function(item)
  local dir = vim.loop.fs_scandir(item.parent_path)
  if dir then
    local file = vim.loop.fs_scandir_next(dir)
    while file do
      local stat = vim.loop.fs_stat(utils.path_join(item.parent_path, file))
      if stat ~= nil and stat.type == "file" then
        if file ~= item.name then
          for _, ruleConfig in pairs(pattern_matcher.config) do
            local pattern = ruleConfig["pattern"]
            local item_name = item.name
            if ruleConfig["ignore_case"] then
              item_name = item_name:lower()
            end
            if file:match(pattern) then
              for _, patternFile in pairs(ruleConfig["files"] or {}) do
                if ruleConfig["ignore_case"] then
                  patternFile = patternFile:lower()
                end
                local result = globtopattern.globtopattern(file:gsub(pattern, patternFile))

                if item_name:match(result) then
                  return utils.path_join(item.parent_path, file)
                end
              end
            end
          end
        end
      end
      file = vim.loop.fs_scandir_next(dir)
    end
  end
  return nil
end

--- Checks if file-nesting module is enabled by config
---@return boolean
function M.is_enabled()
  return next(M.config) ~= nil
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

--- Returns `item` nesting parent path if exists
---@return string?
function M.get_parent(item)
  if item.type ~= "file" then
    return nil
  end
  for _, matcher in pairs(matchers) do
    if matcher.enabled then
      local parent = matcher.get_parent(item)
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
        return true
      end
    end
  end

  return false
end

--- Checks if `target` should be nested into `base`
---@return boolean
function M.should_nest_file(base, target)
  local ext_lookup = M.exts[base.exts]

  return utils.truthy(
    base.base == target.base and ext_lookup and iter(ext_lookup):find(target.exts)
  )
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
  for key, value in pairs(matchers) do
    if next(value.config) ~= nil then
      value.enabled = true
    end
  end
  M.config = config or {}
end

return M
