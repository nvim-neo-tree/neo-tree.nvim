local highlights = require("neo-tree.ui.highlights")

local filesystem = {
  window = {
    position = "left",
    width = 40,
    -- Mappings for tree window. See https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/sources/filesystem/commands.lua
    -- for built-in commands. You can also create your own commands by
    -- providing a function instead of a string. See the built-in
    -- commands for examples.
    mappings = {
      ["<2-LeftMouse>"] = "example_command",
      ["<cr>"] = "example_command",
      ["D"] = "show_debug_info",
    },
  },
  before_render = function(state)
    -- This function is called after the file system has been scanned,
    -- but before the tree is rendered. You can use this to gather extra
    -- data that can be used in the renderers.
    print("before_render")
  end,
  -- This section provides the renderers that will be used to render the tree.
  -- The first level is the node type.
  -- For each node type, you can specify a list of components to render.
  -- Components are rendered in the order they are specified.
  -- The first field in each component is the name of the function to call.
  -- The rest of the fields are passed to the function as the "config" argument.
  renderers = {
    directory = {
      {
        "icon",
        folder_closed = "",
        folder_open = "",
        padding = " ",
      },
      { "name" },
    },
    file = {
      {
        "icon",
        default = "*",
        padding = " ",
      },
      { "name" },
    },
  },
}

return filesystem
