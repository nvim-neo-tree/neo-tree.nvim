local compat = {}
---@return boolean
compat.noref = function()
  return vim.fn.has("nvim-0.10") == 1 and true or {} --[[@as boolean]]
end

---source: https://github.com/Validark/Lua-table-functions/blob/master/table.lua
---Moves elements [f, e] from array a1 into a2 starting at index t
---table.move implementation
---@generic T: table
---@param a1 T from which to draw elements from range
---@param f integer starting index for range
---@param e integer ending index for range
---@param t integer starting index to move elements from a1 within [f, e]
---@param a2 T the second table to move these elements to
---@default a2 = a1
---@returns a2
local table_move = function(a1, f, e, t, a2)
  a2 = a2 or a1
  t = t + e

  for i = e, f, -1 do
    t = t - 1
    a2[t] = a1[i]
  end

  return a2
end
---source:
compat.table_move = table.move or table_move

---@vararg any
local table_pack = function(...)
  -- Returns a new table with parameters stored into an array, with field "n" being the total number of parameters
  local t = { ... }
  ---@diagnostic disable-next-line: inject-field
  t.n = #t
  return t
end
compat.table_pack = table.pack or table_pack

return compat
