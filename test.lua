local utils = require("neo-tree.utils")

local base_path = debug.getinfo(utils.truthy).source:match("@(.*)/utils.lua$")
print(base_path)
local config_path = base_path .. utils.path_separator .. "defaults.lua"
local text = vim.fn.readfile(config_path)
if text == nil then
  error("Could not read neo-tree.defaults")
end
local config = {}
for _, line in ipairs(text) do
  table.insert(config, line)
  if line == "}" then
    break
  end
end

vim.api.nvim_put(config, "l", true, false)

local highlights = require("neo-tree.ui.highlights")

local config = {
  -- The default_source is the one used when calling require('neo-tree').show()
  -- without a source argument.
  default_source = "filesystem",
  -- popup_border_style is for input and confirmation dialogs.
  -- Configurtaion of floating window is done in the individual source sections.
  popup_border_style = "NC", -- "double", "none", "rounded", "shadow", "single" or "solid"
  -- "NC" is a special style that works well with NormalNC set
  enable_git_status = true,
  enable_diagnostics = true,
  open_files_in_last_window = true, -- false = open files in top left window
  log_level = "info", -- "trace", "debug", "info", "warn", "error", "fatal"
  log_to_file = false, -- true, false, "/path/to/file.log", use :NeoTreeLogs to show the file
  --open_files_in_last_window = true -- true = open files in last window visited
  --
  --event_handlers = {
  --  {
  --    event = "before_render",
  --    handler = function (state)
  --      -- add something to the state that can be used by custom components
  --    end
  --  },
  --  {
  --    event = "file_opened",
  --    handler = function(file_path)
  --      --auto close
  --      require("neo-tree").close_all()
  --    end
  --  },
  --  {
  --    event = "file_renamed",
  --    handler = function(args)
  --      -- fix references to file
  --      print(args.source, " renamed to ", args.destination)
  --    end
  --  },
  --  {
  --    event = "file_moved",
  --    handler = function(args)
  --      -- fix references to file
  --      print(args.source, " moved to ", args.destination)
  --    end
  --  },
  --},
  filesystem = {
    follow_current_file = false, -- This will find and focus the file in the
    -- active buffer every time the current file is changed while the tree is open.
    use_libuv_file_watcher = false, -- This will use the OS level file watchers
    -- to detect changes instead of relying on nvim autocmd events.
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
        ["z"] = "close_all_nodes",
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
        -- {
        --   "symlink_target",
        --   highlight = highlights.SYMBOLIC_LINK_TARGET,
        -- },
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
        {
          "name",
          use_git_status_colors = true,
        },
        -- {
        --   "symlink_target",
        --   highlight = highlights.SYMBOLIC_LINK_TARGET,
        -- },
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
  },
  buffers = {
    window = {
      position = "left",
      width = 40,
      -- Mappings for tree window. See https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/sources/filesystem/commands.lua
      -- for built-in commands. You can also create your own commands by
      -- providing a function instead of a string. See the built-in
      -- commands for examples.
      mappings = {
        ["<2-LeftMouse>"] = "open",
        ["<cr>"] = "open",
        ["S"] = "open_split",
        ["s"] = "open_vsplit",
        ["<bs>"] = "navigate_up",
        ["."] = "set_root",
        ["R"] = "refresh",
        ["a"] = "add",
        ["d"] = "delete",
        ["r"] = "rename",
        ["c"] = "copy_to_clipboard",
        ["x"] = "cut_to_clipboard",
        ["p"] = "paste_from_clipboard",
        ["bd"] = "buffer_delete",
      },
    },
    bind_to_cwd = true,
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
        { "diagnostics", errors_only = true },
        { "clipboard", highlight = highlights.DIM_TEXT },
      },
      file = {
        {
          "icon",
          default = "*",
          padding = " ",
        },
        { "name" },
        { "bufnr" },
        { "diagnostics" },
        { "git_status", highlight = highlights.DIM_TEXT },
        { "clipboard", highlight = highlights.DIM_TEXT },
      },
    },
  },
  git_status = {
    window = {
      position = "left",
      width = 40,
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
        ["R"] = "refresh",
        ["d"] = "delete",
        ["r"] = "rename",
        ["c"] = "copy_to_clipboard",
        ["x"] = "cut_to_clipboard",
        ["p"] = "paste_from_clipboard",
        ["A"] = "git_add_all",
        ["gu"] = "git_unstage_file",
        ["ga"] = "git_add_file",
        ["gr"] = "git_revert_file",
        ["gc"] = "git_commit",
        ["gp"] = "git_push",
        ["gg"] = "git_commit_and_push",
      },
    },
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
        { "diagnostics", errors_only = true },
      },
      file = {
        {
          "icon",
          default = "*",
          padding = " ",
        },
        { "name" },
        { "diagnostics" },
        {
          "git_status",
          highlight = highlights.DIM_TEXT,
        },
      },
    },
  },
}
