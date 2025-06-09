local M = {}

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

---@generic T : table
---@param path string
---@param tbl T
---@param accesses string[]
---@param missed_paths table<string, true?>
---@return T mocked_tbl
local function mock_recursive(path, tbl, accesses, missed_paths, track_missed)
  local mock_table = {}

  ---@class neotree.health.Mock.Metatable<T> : metatable
  ---@field accesses string[]
  local mt = {
    __original_table = tbl,
    accesses = accesses,
  }

  ---@return string[] missed_paths
  mt.get_missed_paths = function()
    ---@type string[]
    local missed_list = {}
    if track_missed then
      for p, _ in pairs(missed_paths) do
        table.insert(missed_list, p)
      end
    end
    table.sort(missed_list)
    return missed_list
  end

  mt.__index = function(_, key)
    local path_segment
    if type(key) == "number" then
      path_segment = ("[%02d]"):format(key)
    else
      path_segment = tostring(key)
    end

    local full_path
    if path == "" then
      full_path = path_segment
    elseif type(key) == "number" then
      full_path = path .. path_segment
    else
      full_path = path .. "." .. path_segment
    end

    -- Track accesses and missed accesses
    mt.accesses[#mt.accesses + 1] = full_path
    if track_missed then
      missed_paths[full_path] = nil
    end

    local value = mt.__original_table[key]

    if type(value) == "table" then
      return mock_recursive(full_path, value, mt.accesses, missed_paths, track_missed)
    end
    return value
  end

  setmetatable(mock_table, mt)
  return mock_table
end

--- Wraps a given table in a special mock table that tracks all accesses
--- (reads) to its fields and sub-fields. Optionally tracks unaccessed fields.
---
---@generic T : table
---@param name string The base name for the table, this forms the root of the access paths.
---@param tbl T The table to be mocked.
---@param track_missed boolean? Track which fields were NOT accessed.
---@return T mocked
function M.mock(name, tbl, track_missed)
  local accesses = {}
  local path_set = {}
  track_missed = track_missed or false

  if track_missed then
    -- Generate another mock table and fully traverse that one first
    local root_mock = M.mock(name, tbl, false)

    ---@param current_table table
    local function deep_traverse_mock(current_table)
      ---@type neotree.health.Mock.Metatable
      local mt = getmetatable(current_table)
      for k, v in pairs(mt.__original_table) do
        if type(v) == "table" then
          deep_traverse_mock(current_table[k])
        else
          mt.__index(nil, k)
        end
      end
    end
    deep_traverse_mock(root_mock)
    accesses = getmetatable(root_mock).accesses
    for _, path in ipairs(accesses) do
      path_set[path] = true
    end
  end

  -- Start the recursive mocking process, passing all necessary shared tracking data.
  return mock_recursive(name, tbl, accesses, path_set, track_missed)
end

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
  local matched, errmsg, errinfo
  M.namestack[#M.namestack + 1] = name
  if type(validator) == "string" then
    matched = M.match(value, validator)
  elseif type(validator) == "table" then
    for _, v in ipairs(validator) do
      matched = M.match(value, v)
      if matched then
        break
      end
    end
  elseif type(validator) == "function" and value ~= nil then
    local ok = false
    if on_invalid then
      M.errfuncs[#M.errfuncs + 1] = on_invalid
    end
    if track_missed and type(value) == "table" then
      value = M.mock(name, value, true)
    end
    ok, matched, errinfo = pcall(validator, value)
    if on_invalid then
      M.errfuncs[#M.errfuncs] = nil
    end
    if not ok then
      errinfo = matched
      matched = false
    elseif matched == nil then
      matched = true
    end
  end
  matched = matched or (optional and value == nil) or false

  if not matched then
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
    return matched, missed
  end
  return matched
end

return M
