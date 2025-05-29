local typecheck = {}

---Type but also supports "callable" like neovim does.
---@see _G.type
---@param obj any
---@param expected neotree.LuaType
function typecheck.match(obj, expected)
  if type(obj) == expected then
    return true
  end
  if expected == "callable" and vim.is_callable(obj) then
    return true
  end
  return false
end

---@alias neotree.LuaType type|"callable"
---@alias neotree.ValidatorFunction<T> fun(value: T):boolean?,string?
---@alias neotree.Validator<T> elem_or_list<neotree.LuaType>|neotree.ValidatorFunction<T>

---@type (fun(err:string))[]
local errfuncs = {}
---A comprehensive version of vim.validate that makes it easy to validate nested tables of various types
---@generic T
---@param name string
---@param value T
---@param validator neotree.Validator<T>
---@param optional? boolean Whether value can be nil
---@param message? string message when validation fails
---@param on_invalid? fun(err: string, value: T) What to do when a (nested) validation fails
---@return boolean valid
function typecheck.validate(name, value, validator, optional, message, on_invalid)
  local matched, errmsg, errinfo
  if type(validator) == "string" then
    matched = typecheck.match(value, validator)
  elseif type(validator) == "table" then
    for _, v in ipairs(validator) do
      matched = typecheck.match(value, v)
      if matched then
        break
      end
    end
  elseif vim.is_callable(validator) and value ~= nil then
    local ok = false
    if on_invalid then
      errfuncs[#errfuncs + 1] = on_invalid
    end
    ok, matched, errinfo = pcall(validator, value)
    if not ok then
      errinfo = matched
      matched = false
    elseif matched == nil then
      matched = true
    end
    if on_invalid then
      errfuncs[#errfuncs] = nil
    end
  end
  matched = matched or (optional and value == nil) or false

  if not matched then
    ---@type string
    local expected
    if vim.is_callable(validator) then
      expected = "?"
    else
      local expected_types = type(validator) == "string" and { validator } or validator
      ---@cast expected_types -string
      if optional then
        expected_types[#expected_types + 1] = "nil"
      end
      ---@cast expected_types -function
      expected = table.concat(expected_types, "|")
    end

    errmsg = ("%s: %s, got %s"):format(
      name,
      message or ("expected " .. expected),
      message and value or type(value)
    )
    if errinfo then
      errmsg = errmsg .. ", Info: " .. errinfo
    end
    local errfunc = errfuncs[#errfuncs] or function(err)
      error(err, 2)
    end
    errfunc(errmsg)
  end
  return matched
end

return typecheck
