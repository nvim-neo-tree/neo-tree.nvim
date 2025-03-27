-- Need the absolute path as when doing the testing we will issue things like `tcd` to change directory
-- to where our temporary filesystem lives
local root_dir = vim.fn.fnamemodify(vim.trim(vim.fn.system("git rev-parse --show-toplevel")), ":p")

package.path = string.format("%s;%s?.lua;%s?/init.lua", package.path, root_dir, root_dir)

vim.opt.packpath:prepend(root_dir .. ".dependencies/site")

vim.opt.rtp = {
  root_dir,
  vim.env.VIMRUNTIME,
}

vim.cmd([[
  filetype on
  packadd plenary.nvim
  packadd nui.nvim
  packadd nvim-web-devicons
]])

vim.opt.swapfile = false

vim.cmd([[
  runtime plugin/neo-tree.lua
]])

-- For debugging
P = vim.print
