-- Need the absolute path as when doing the testing we will issue things like `tcd` to change directory
-- to where our temporary filesystem lives
vim.opt.rtp = {
  vim.fn.fnamemodify(vim.trim(vim.fn.system("git rev-parse --show-toplevel")), ":p"),
  "/plugins",
  vim.env.VIMRUNTIME,
}

vim.cmd([[
  filetype on
  packadd plenary.nvim
  packadd nui.nvim
]])

vim.opt.swapfile = false

vim.cmd([[
  runtime plugin/neo-tree.vim
]])

-- For debugging
P = function(...)
  print(table.unpack(vim.tbl_map(vim.inspect, { ... })))
end
