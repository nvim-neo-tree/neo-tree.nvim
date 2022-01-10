local highlights = require("neo-tree.ui.highlights")

local filesystem = {
  window = {
    -- see https://github.com/MunifTanjim/nui.nvim/tree/main/lua/nui/popup
    -- for possible options. These can also be functions that return these
    -- options.
    position = "left", -- left, right, float
    width = 40, -- applies to left and right positions
    -- settings that apply to float position only
    popup = {
      size = {
        height = "80%",
        width = "50%",
      },
      position = "50%", -- 50% means center it
      -- you can also specify border here, if you want a different setting from
      -- the global popup_border_style.
    },
    -- Mappings for tree window. See https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/sources/filesystem/commands.lua
    -- for built-in commands. You can also create your own commands by
    -- providing a function instead of a string. See the built-in
    -- commands for examples.
    mappings = {
      ["<2-LeftMouse>"] = "open",
      ["<cr>"] = "open",
      ["S"] = "open_split",
      ["s"] = "open_vsplit",
      ["C"] = "close_node",
      ["<bs>"] = "navigate_up",
      ["."] = "set_root",
      ["H"] = "toggle_hidden",
      ["I"] = "toggle_gitignore",
      ["R"] = "refresh",
      ["/"] = "filter_as_you_type",
      ["f"] = "filter_on_submit",
      ["<C-x>"] = "clear_filter",
      ["a"] = "add",
      ["d"] = "delete",
      ["r"] = "rename",
      ["c"] = "copy_to_clipboard",
      ["x"] = "cut_to_clipboard",
      ["p"] = "paste_from_clipboard",
    },
  },
  --find_command = "fd",
  search_limit = 50, -- max number of search results when using filters
  filters = {
    show_hidden = false,
    respect_gitignore = true,
  },
  bind_to_cwd = true, -- true creates a 2-way binding between vim's cwd and neo-tree's root
  before_render = function(state)
    -- This function is called after the file system has been scanned,
    -- but before the tree is rendered. You can use this to gather extra
    -- data that can be used in the renderers.
    local utils = require("neo-tree.utils")
    state.git_status_lookup = utils.get_git_status()
    state.diagnostics_lookup = utils.get_diagnostic_counts()
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
      { "current_filter" },
      { "name" },
      {
        "clipboard",
        highlight = highlights.DIM_TEXT,
      },
      { "diagnostics", errors_only = true },
      --{ "git_status" },
    },
    file = {
      {
        "icon",
        default = "*",
        padding = " ",
      },
      --{ "hello_node", highlight = "Normal" },
      { "name" },
      {
        "clipboard",
        highlight = highlights.DIM_TEXT,
      },
      { "diagnostics" },
      {
        "git_status",
        highlight = highlights.DIM_TEXT,
      },
    },
  },
}

return filesystem
