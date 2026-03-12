local root_dir = vim.fs.find("neo-tree.nvim", { upward = true, limit = 1 })[1]
assert(root_dir, "no neo-tree found")

package.path = ("%s;%s/?.lua;%s/?/init.lua"):format(package.path, root_dir, root_dir)

vim.opt.runtimepath = {
  root_dir,
  vim.env.VIMRUNTIME,
}

local utils = require("neo-tree.utils")
local deps_dir = utils.path_join(root_dir, ".dependencies")
local deps = {}
for basename, type in vim.fs.dir(deps_dir) do
  assert(type == "directory")
  deps[#deps + 1] = utils.path_join(deps_dir, basename)
  -- add each dep
end
vim.opt.runtimepath:append(deps)

vim.env.NEOTREE_TESTING = "true"

-- need this for tests to work
vim.cmd.source(root_dir .. "/plugin/neo-tree.lua")

vim.g.mapleader = " "
vim.keymap.set("n", "<Leader>e", "<Cmd>Neotree<CR>")
