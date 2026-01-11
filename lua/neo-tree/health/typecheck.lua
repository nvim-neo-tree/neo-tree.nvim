local M = {}
local utils = require("neo-tree.health.utils")

---Like type() but also supports "callable" like neovim does.
---@see _G.type
---@param obj any
---@param expected neotree.LuaType
function M.match(obj, expected)
  if type(obj) == expected then
    return true
  end
  if expected == "callable" and vim.is_callable(obj) then
    return true
  end
  return false
end

---@alias neotree.LuaType type|"callable"
---@alias neotree.health.ValidatorFunction<T> fun(value: T):boolean?,string?
---@alias neotree.health.Validator<T> elem_or_list<neotree.LuaType>|neotree.health.ValidatorFunction<T>

---@type (fun(err:string))[]
M.errfuncs = {}
---@type string[]
M.namestack = {}

---A comprehensive version of vim.validate that makes it easy to validate nested tables of various types
---@generic T
---@param name string
---@param value T
---@param validator neotree.health.Validator<T>
---@param optional? boolean Whether value can be nil
---@param message? string message when validation fails
---@param on_invalid? fun(err: string, value: T):boolean? What to do when a (nested) validation fails, return true to throw error
---@param track_missed? boolean Whether to return a second table that contains every non-checked field
---@return boolean valid
---@return string[]? missed
function M.validate(name, value, validator, optional, message, on_invalid, track_missed)
  local valid, errmsg, errinfo
  M.namestack[#M.namestack + 1] = name
  if type(validator) == "string" then
    valid = M.match(value, validator)
  elseif type(validator) == "table" then
    for _, v in ipairs(validator) do
      valid = M.match(value, v)
      if valid then
        break
      end
    end
  elseif type(validator) == "function" and value ~= nil then
    local ok = false
    if on_invalid then
      M.errfuncs[#M.errfuncs + 1] = on_invalid
    end
    if track_missed and type(value) == "table" then
      value = utils.mock(name, value, true)
    end
    ok, valid, errinfo = pcall(validator, value)
    if on_invalid then
      M.errfuncs[#M.errfuncs] = nil
    end
    if not ok then
      errinfo = valid
      valid = false
    elseif valid == nil then
      -- for conciseness, assume that it's valid
      valid = true
    end
  end
  valid = valid or (optional and value == nil) or false

  if not valid then
    ---@type string
    local expected
    if vim.is_callable(validator) then
      expected = "?"
    else
      ---@cast validator -function
      local expected_types = type(validator) == "string" and { validator } or validator
      ---@cast expected_types -string
      if optional then
        expected_types[#expected_types + 1] = "nil"
      end
      expected = table.concat(expected_types, "|")
    end

    errmsg = ("%s: %s, got %s"):format(
      table.concat(M.namestack, "."),
      message or ("expected " .. expected),
      message and value or type(value)
    )
    if errinfo then
      errmsg = errmsg .. ", Info: " .. errinfo
    end
    local errfunc = M.errfuncs[#M.errfuncs]
    local should_error = not errfunc or errfunc(errmsg)
    if should_error then
      M.namestack[#M.namestack] = nil
      error(errmsg, 2)
    end
  end
  M.namestack[#M.namestack] = nil

  if track_missed then
    local missed = getmetatable(value).get_missed_paths()
    return valid, missed
  end
  return valid
end

return M
