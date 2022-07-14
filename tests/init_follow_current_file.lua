-- Need the absolute path as when doing the testing we will issue things like `tcd` to change directory
-- to where our temporary filesystem lives
local root_dir = vim.fn.fnamemodify(vim.trim(vim.fn.system("git rev-parse --show-toplevel")), ":p")

package.path = package.path .. ";" .. root_dir .. "?.lua"

vim.opt.packpath:prepend(string.format("%s", root_dir .. ".testcache/site"))

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

require("neo-tree").setup({
  filesystem = {
    netrw_hijack_behavior = "disabled",
    follow_current_file = true,
  },
})

vim.opt.swapfile = false

vim.cmd([[
  runtime plugin/neo-tree.vim
]])

-- For debugging
P = function(...)
  print(unpack(vim.tbl_map(vim.inspect, { ... })))
end
