require("tests.repro.base")

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.cmd([[runtime plugin/neo-tree.lua]])
    require("neo-tree").setup({
      filesystem = {
        hijack_netrw_behavior = "open_default",
      },
    })
  end,
})

vim.opt.swapfile = false
