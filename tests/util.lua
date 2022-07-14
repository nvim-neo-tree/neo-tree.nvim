local mod = {
  fs = require("tests.helpers.fs"),
}

function mod.clear_environment()
  -- Create fresh window
  vim.cmd("top new | wincmd o")
  local keepbufnr = vim.api.nvim_get_current_buf()
  -- Clear ALL neo-tree state
  require("neo-tree.sources.manager")._clear_state()
  -- Cleanup any remaining buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= keepbufnr then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  assert(#vim.api.nvim_tabpage_list_wins(0) == 1, "Failed to properly clear tab")
  assert(#vim.api.nvim_list_bufs() == 1, "Failed to properly clear buffers")
end

return mod
