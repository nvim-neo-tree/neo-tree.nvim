-- Need the absolute path as when doing the testing we will issue things like `tcd` to change directory
-- to where our temporary filesystem lives
vim.opt.rtp = {
  vim.fn.fnamemodify(vim.trim(vim.fn.system("git rev-parse --show-toplevel")), ":p"),
  "/plugins/nui.nvim",
  "/plugins/plenary.nvim",
  "/plugins/neo-tree.nvim",
  vim.env.VIMRUNTIME,
}

vim.cmd([[
  filetype on
  runtime plugin/plenary.vim
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
  print(table.unpack(vim.tbl_map(vim.inspect, { ... })))
end
