---A collection of utils for making mock tables - tables that wrap other tables and track missed accesses
local M = {}
---@generic T : table
---@param path string
---@param tbl T
---@param accesses string[]
---@param missed_paths table<string, true?>
---@param track_missed boolean?
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
---@param track_unaccessed boolean?
---@return T mocked
function M.mock(name, tbl, track_unaccessed)
  local accesses = {}
  local path_set = {}
  track_unaccessed = track_unaccessed or false

  if track_unaccessed then
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
  return mock_recursive(name, tbl, accesses, path_set, track_unaccessed)
end

return M
