local root_dir = vim.fs.find("plugin", { upward = true, type = "directory" })

vim.opt.packpath:prepend(root_dir .. ".dependencies")

vim.opt.rtp = {
  root_dir,
  vim.env.VIMRUNTIME,
}

-- For debugging
P = vim.print
