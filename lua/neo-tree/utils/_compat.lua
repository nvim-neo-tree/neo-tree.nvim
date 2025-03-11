local compat = {}
---@return boolean
compat.noref = function()
  return vim.fn.has("nvim-0.10") == 1 and true or {} --[[@as boolean]]
end
return compat
