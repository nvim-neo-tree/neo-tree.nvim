require("tests.repro.base")

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = "editor",
      row = 10,
      col = 10,
      width = 10,
      height = 10,
    })
  end,
})
