local root = vim.fs.find({ "neo-tree.nvim" }, { upward = true })[1]
local deps_dir = root .. "/.dependencies/pack/vendor/start"
return {
  {
    "folke/snacks.nvim",
    dir = deps_dir .. "/snacks.nvim",
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    dir = root,
  },
  {
    "MunifTanjim/nui.nvim",
    dir = deps_dir .. "/nui.nvim",
  },
  {
    "nvim-tree/nvim-web-devicons",
    dir = deps_dir .. "/nvim-web-devicons",
  },
  {
    "nvim-lua/plenary.nvim",
    dir = deps_dir .. "/plenary.nvim",
  },
}
