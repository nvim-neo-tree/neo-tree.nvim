local compat = {}
compat.noref = function()
  return vim.fn.has("nvim-0.10") == 1 and true or {}
end
return compat
