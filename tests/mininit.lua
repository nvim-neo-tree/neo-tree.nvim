vim.opt.rtp = { ".", vim.env.VIMRUNTIME }

vim.cmd([[
  packadd plenary.nvim
  packadd nui.nvim
]])

require("neo-tree").setup()

-- For debugging
P = function(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
  return objects
end
