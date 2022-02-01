-- Need the absolute path as when doing the testing we will issue things like `tcd` to change directory
-- to where our temporary filesystem lives
vim.opt.rtp = {
  vim.fn.fnamemodify(vim.trim(vim.fn.system("git rev-parse --show-toplevel")), ":p"),
  vim.env.VIMRUNTIME,
}

vim.cmd([[
  packadd plenary.nvim
  packadd nui.nvim
]])

require("neo-tree").setup()

vim.opt.swapfile = false

vim.cmd([[
  runtime plugin/neo-tree.vim
]])

-- For debugging
P = function(...)
  print(unpack(vim.tbl_map(vim.inspect, { ... })))
end
