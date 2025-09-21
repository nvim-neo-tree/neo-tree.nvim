local root_dir = vim.fs.find("neo-tree.nvim", { upward = true, limit = 1 })[1]
assert(root_dir, "no neo-tree found")

package.path = ("%s;%s/?.lua;%s/?/init.lua"):format(package.path, root_dir, root_dir)
vim.opt.packpath:prepend(root_dir .. "/.dependencies")

vim.opt.rtp = {
  root_dir,
  vim.env.VIMRUNTIME,
}

-- need this for tests to work
vim.cmd.source(root_dir .. "/plugin/neo-tree.lua")

vim.g.mapleader = " "
vim.keymap.set("n", "<Leader>e", "<Cmd>Neotree<CR>")
