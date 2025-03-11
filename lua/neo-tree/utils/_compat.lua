local compat = {}
compat.DEEPCOPY_NOREF = vim.fn.has("nvim-v0.9") and true or {}
return compat
