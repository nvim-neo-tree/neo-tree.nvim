local root_dir = vim.fs.find("plugin", { upward = true, limit = 1 })[1]
assert(root_dir, "no neo-tree found")

vim.opt.packpath:prepend(root_dir .. ".dependencies")

vim.opt.rtp = {
  root_dir,
  vim.env.VIMRUNTIME,
}
