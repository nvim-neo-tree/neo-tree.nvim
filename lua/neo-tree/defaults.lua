---See https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/types/config.lua
---for type definitions.
---@type NeotreeConfig
local config = {
  sources = {
    "filesystem",
    "buffers",
    "git_status",
    -- "document_symbols",
  },
  add_blank_line_at_top = false,
  auto_clean_after_session_restore = false,
  close_if_last_window = false,
  default_source = "filesystem",
  enable_diagnostics = true,
  enable_git_status = true,
  enable_modified_markers = true,
  enable_opened_markers = true,
  enable_refresh_on_write = true,
  enable_cursor_hijack = false,
  enable_normal_mode_for_inputs = false,
  git_status_async = true,
  git_status_async_options = {
    batch_size = 1000,
    batch_delay = 10,
    max_lines = 10000,
  },
  hide_root_node = false,
  retain_hidden_root_indent = false,
  log_level = "info",
  log_to_file = false,
  open_files_in_last_window = true,
  open_files_do_not_replace_types = { "terminal", "Trouble", "qf", "edgy" },
  popup_border_style = "NC",
  resize_timer_interval = 500,
  sort_case_insensitive = false,
  sort_function = nil,
  use_popups_for_input = true,
  use_default_mappings = true,
}

---@type NeotreeConfig.source_selector
config.source_selector = {
  winbar = false,
  statusline = false,
  show_scrolled_off_parent_node = false,
  sources = {
    { source = "filesystem" },
    { source = "buffers" },
    { source = "git_status" },
  },
  content_layout = "start",
  tabs_layout = "equal",
  truncation_character = "…",
  tabs_min_width = nil,
  tabs_max_width = nil,
  padding = 0,
  separator = { left = "▏", right = "▕" },
  separator_active = nil,
  show_separator_on_edge = false,
  highlight_tab = "NeoTreeTabInactive",
  highlight_tab_active = "NeoTreeTabActive",
  highlight_background = "NeoTreeTabInactive",
  highlight_separator = "NeoTreeTabSeparatorInactive",
  highlight_separator_active = "NeoTreeTabSeparatorActive",
}

---@type NeotreeConfig.components
config.default_component_configs = {
  container = {
    enable_character_fade = true,
    width = "100%",
    right_padding = 0,
  },
  diagnostics = {
    symbols = {
      hint = "H",
      info = "I",
      warn = "!",
      error = "X",
    },
    highlights = {
      hint = "DiagnosticSignHint",
      info = "DiagnosticSignInfo",
      warn = "DiagnosticSignWarn",
      error = "DiagnosticSignError",
    },
  },
  indent = {
    indent_size = 2,
    padding = 1,
    with_markers = true,
    indent_marker = "│",
    last_indent_marker = "└",
    highlight = "NeoTreeIndentMarker",
    with_expanders = nil,
    expander_collapsed = "",
    expander_expanded = "",
    expander_highlight = "NeoTreeExpander",
  },
  icon = {
    folder_closed = "",
    folder_open = "",
    folder_empty = "󰉖",
    folder_empty_open = "󰷏",
    default = "*",
    highlight = "NeoTreeFileIcon",
  },
  modified = {
    symbol = "[+] ",
    highlight = "NeoTreeModified",
  },
  name = {
    trailing_slash = false,
    highlight_opened_files = false,
    use_git_status_colors = true,
    highlight = "NeoTreeFileName",
  },
  git_status = {
    symbols = {
      -- you can set any of these to an empty string to not show them
      added = "✚",
      deleted = "✖",
      modified = "",
      renamed = "󰁕",
      untracked = "",
      ignored = "",
      unstaged = "󰄱",
      staged = "",
      conflict = "",
    },
    align = "right",
  },
  file_size = {
    enabled = true,
    required_width = 64,
  },
  type = {
    enabled = true,
    required_width = 110,
  },
  last_modified = {
    enabled = true,
    required_width = 88,
  },
  created = {
    enabled = false,
    required_width = 120,
  },
  symlink_target = {
    enabled = false,
  },
}

---@type NeotreeConfig.renderers
config.renderers = {
  directory = {
    { "indent" },
    { "icon" },
    { "current_filter" },
    {
      "container",
      content = {
        { "name", zindex = 10 },
        {
          "symlink_target",
          zindex = 10,
          highlight = "NeoTreeSymbolicLinkTarget",
        },
        { "clipboard", zindex = 10 },
        {
          "diagnostics",
          errors_only = true,
          zindex = 20,
          align = "right",
          hide_when_expanded = true,
        },
        { "git_status", zindex = 10, align = "right", hide_when_expanded = true },
        { "file_size", zindex = 10, align = "right" },
        { "type", zindex = 10, align = "right" },
        { "last_modified", zindex = 10, align = "right" },
        { "created", zindex = 10, align = "right" },
      },
    },
  },
  file = {
    { "indent" },
    { "icon" },
    {
      "container",
      content = {
        {
          "name",
          zindex = 10,
        },
        {
          "symlink_target",
          zindex = 10,
          highlight = "NeoTreeSymbolicLinkTarget",
        },
        { "clipboard", zindex = 10 },
        { "bufnr", zindex = 10 },
        { "modified", zindex = 20, align = "right" },
        { "diagnostics", zindex = 20, align = "right" },
        { "git_status", zindex = 10, align = "right" },
        { "file_size", zindex = 10, align = "right" },
        { "type", zindex = 10, align = "right" },
        { "last_modified", zindex = 10, align = "right" },
        { "created", zindex = 10, align = "right" },
      },
    },
  },
  message = {
    { "indent", with_markers = false },
    { "name", highlight = "NeoTreeMessage" },
  },
  terminal = {
    { "indent" },
    { "icon" },
    { "name" },
    { "bufnr" },
  },
}

---@type table<string, NeotreeConfig.nesting_rule>
config.nesting_rules = {}

---Global custom commands that will be available in all sources (if not overridden in `opts[source_name].commands`)
---
---You can then reference the custom command by adding a mapping to it:
---   globally    -> `opts.window.mappings`
---   locally     -> `opt[source_name].window.mappings` to make it source specific.
---
---commands = {              |  window {                 |  filesystem {
---  hello = function()      |    mappings = {           |    commands = {
---    print("Hello world")  |      ["<C-c>"] = "hello"  |      hello = function()
---  end                     |    }                      |        print("Hello world in filesystem")
---}                         |  }                        |      end
---
---see `:h neo-tree-custom-commands-global`
---@type NeotreeConfig.mappings
config.commands = {}

---@type NeotreeConfig.window
config.window = {
  -- see https://github.com/MunifTanjim/nui.nvim/tree/main/lua/nui/popup for
  -- possible options. These can also be functions that return these options.
  position = "left",
  width = 40,
  height = 15,
  auto_expand_width = false,
  popup = {
    size = {
      height = "80%",
      width = "50%",
    },
    position = "50%",
  },
  same_level = false,
  insert_as = "child",
  mapping_options = {
    noremap = true,
    nowait = true,
  },
  mappings = {
    ["<space>"] = {
      "toggle_node",
      nowait = false,
    },
    ["<2-LeftMouse>"] = "open",
    ["<cr>"] = "open",
    -- ["<cr>"] = { "open", config = { expand_nested_files = true } }, -- expand nested file takes precedence
    ["<esc>"] = "cancel", -- close preview or floating neo-tree window
    ["P"] = { "toggle_preview", config = { use_float = true, use_image_nvim = false } },
    ["l"] = "focus_preview",
    ["S"] = "open_split",
    -- ["S"] = "split_with_window_picker",
    ["s"] = "open_vsplit",
    -- ["sr"] = "open_rightbelow_vs",
    -- ["sl"] = "open_leftabove_vs",
    -- ["s"] = "vsplit_with_window_picker",
    ["t"] = "open_tabnew",
    -- ["<cr>"] = "open_drop",
    -- ["t"] = "open_tab_drop",
    ["w"] = "open_with_window_picker",
    ["C"] = "close_node",
    ["z"] = "close_all_nodes",
    --["Z"] = "expand_all_nodes",
    ["R"] = "refresh",
    ["a"] = {
      "add",
      config = {
        show_path = "none", -- "none", "relative", "absolute"
      },
    },
    ["A"] = "add_directory", -- also accepts the config.show_path and config.insert_as options.
    ["d"] = "delete",
    ["r"] = "rename",
    ["y"] = "copy_to_clipboard",
    ["x"] = "cut_to_clipboard",
    ["p"] = "paste_from_clipboard",
    ["c"] = "copy", -- takes text input for destination, also accepts the config.show_path and config.insert_as options
    ["m"] = "move", -- takes text input for destination, also accepts the config.show_path and config.insert_as options
    ["e"] = "toggle_auto_expand_width",
    ["q"] = "close_window",
    ["?"] = "show_help",
    ["<"] = "prev_source",
    [">"] = "next_source",
  },
}

---@type NeotreeConfig.filesystem
config.filesystem = {
  window = {
    mappings = {
      ["H"] = "toggle_hidden",
      ["/"] = "fuzzy_finder",
      ["D"] = "fuzzy_finder_directory",
      --["/"] = "filter_as_you_type", -- this was the default until v1.28
      ["#"] = "fuzzy_sorter", -- fuzzy sorting using the fzy algorithm
      -- ["D"] = "fuzzy_sorter_directory",
      ["f"] = "filter_on_submit",
      ["<C-x>"] = "clear_filter",
      ["<bs>"] = "navigate_up",
      ["."] = "set_root",
      ["[g"] = "prev_git_modified",
      ["]g"] = "next_git_modified",
      ["i"] = "show_file_details",
      ["o"] = { "show_help", nowait = false, config = { title = "Order by", prefix_key = "o" } },
      ["oc"] = { "order_by_created", nowait = false },
      ["od"] = { "order_by_diagnostics", nowait = false },
      ["og"] = { "order_by_git_status", nowait = false },
      ["om"] = { "order_by_modified", nowait = false },
      ["on"] = { "order_by_name", nowait = false },
      ["os"] = { "order_by_size", nowait = false },
      ["ot"] = { "order_by_type", nowait = false },
    },
    fuzzy_finder_mappings = { -- define keymaps for filter popup window in fuzzy_finder_mode
      ["<down>"] = "move_cursor_down",
      ["<C-n>"] = "move_cursor_down",
      ["<up>"] = "move_cursor_up",
      ["<C-p>"] = "move_cursor_up",
    },
  },
  async_directory_scan = "auto",
  scan_mode = "shallow",
  bind_to_cwd = true,
  cwd_target = {
    sidebar = "tab",
    current = "window",
  },
  check_gitignore_in_search = true,
  filtered_items = {
    visible = false,
    force_visible_in_empty_folder = false,
    show_hidden_count = true,
    hide_dotfiles = true,
    hide_gitignored = true,
    hide_hidden = true,
    hide_by_name = {
      ".DS_Store",
      "thumbs.db",
      --"node_modules",
    },
    -- uses glob style patterns
    hide_by_pattern = {
      --"*.meta",
      --"*/src/*/tsconfig.json"
    },
    -- remains visible even if other settings would normally hide it
    always_show = {
      --".gitignored",
    },
    -- remains hidden even if visible is toggled to true, this overrides always_show
    never_show = {
      --".DS_Store",
      --"thumbs.db"
    },
    -- uses glob style patterns
    never_show_by_pattern = {
      --".null-ls_*",
    },
  },
  find_by_full_path_words = false,
  find_command = nil,
  find_args = nil,
  group_empty_dirs = false,
  search_limit = 50,
  follow_current_file = {
    enabled = false,
    leave_dirs_open = false,
  },
  hijack_netrw_behavior = "open_default",
  use_libuv_file_watcher = false,
}

---@type NeotreeConfig.buffers
config.buffers = {
  bind_to_cwd = true,
  follow_current_file = {
    enabled = true,
    leave_dirs_open = false,
  },
  group_empty_dirs = true,
  show_unloaded = false,
  terminals_first = false,
  window = {
    mappings = {
      ["<bs>"] = "navigate_up",
      ["."] = "set_root",
      ["bd"] = "buffer_delete",
      ["i"] = "show_file_details",
      ["o"] = { "show_help", nowait = false, config = { title = "Order by", prefix_key = "o" } },
      ["oc"] = { "order_by_created", nowait = false },
      ["od"] = { "order_by_diagnostics", nowait = false },
      ["om"] = { "order_by_modified", nowait = false },
      ["on"] = { "order_by_name", nowait = false },
      ["os"] = { "order_by_size", nowait = false },
      ["ot"] = { "order_by_type", nowait = false },
    },
  },
}

---@type NeotreeConfig.git_status
config.git_status = {
  window = {
    mappings = {
      ["A"] = "git_add_all",
      ["gu"] = "git_unstage_file",
      ["ga"] = "git_add_file",
      ["gr"] = "git_revert_file",
      ["gc"] = "git_commit",
      ["gp"] = "git_push",
      ["gg"] = "git_commit_and_push",
      ["i"] = "show_file_details",
      ["o"] = { "show_help", nowait = false, config = { title = "Order by", prefix_key = "o" } },
      ["oc"] = { "order_by_created", nowait = false },
      ["od"] = { "order_by_diagnostics", nowait = false },
      ["om"] = { "order_by_modified", nowait = false },
      ["on"] = { "order_by_name", nowait = false },
      ["os"] = { "order_by_size", nowait = false },
      ["ot"] = { "order_by_type", nowait = false },
    },
  },
}

---@type NeotreeConfig.document_symbols
config.document_symbols = {
  follow_cursor = false,
  client_filters = "first",
  renderers = {
    root = {
      { "indent" },
      { "icon", default = "C" },
      { "name", zindex = 10 },
    },
    symbol = {
      { "indent", with_expanders = true },
      { "kind_icon", default = "?" },
      {
        "container",
        content = {
          { "name", zindex = 10 },
          { "kind_name", zindex = 20, align = "right" },
        },
      },
    },
  },
  window = {
    mappings = {
      ["<cr>"] = "jump_to_symbol",
      ["o"] = "jump_to_symbol",
      ["A"] = "noop",
      ["d"] = "noop",
      ["y"] = "noop",
      ["x"] = "noop",
      ["p"] = "noop",
      ["c"] = "noop",
      ["m"] = "noop",
      ["a"] = "noop",
      ["/"] = "filter",
      ["f"] = "filter_on_submit",
    },
  },
  kinds = {
    Unknown = { icon = "?", hl = "" },
    Root = { icon = "", hl = "NeoTreeRootName" },
    File = { icon = "󰈙", hl = "Tag" },
    Module = { icon = "", hl = "Exception" },
    Namespace = { icon = "󰌗", hl = "Include" },
    Package = { icon = "󰏖", hl = "Label" },
    Class = { icon = "󰌗", hl = "Include" },
    Method = { icon = "", hl = "Function" },
    Property = { icon = "󰆧", hl = "@property" },
    Field = { icon = "", hl = "@field" },
    Constructor = { icon = "", hl = "@constructor" },
    Enum = { icon = "󰒻", hl = "@number" },
    Interface = { icon = "", hl = "Type" },
    Function = { icon = "󰊕", hl = "Function" },
    Variable = { icon = "", hl = "@variable" },
    Constant = { icon = "", hl = "Constant" },
    String = { icon = "󰀬", hl = "String" },
    Number = { icon = "󰎠", hl = "Number" },
    Boolean = { icon = "", hl = "Boolean" },
    Array = { icon = "󰅪", hl = "Type" },
    Object = { icon = "󰅩", hl = "Type" },
    Key = { icon = "󰌋", hl = "" },
    Null = { icon = "", hl = "Constant" },
    EnumMember = { icon = "", hl = "Number" },
    Struct = { icon = "󰌗", hl = "Type" },
    Event = { icon = "", hl = "Constant" },
    Operator = { icon = "󰆕", hl = "Operator" },
    TypeParameter = { icon = "󰊄", hl = "Type" },
  },
  custom_kinds = {},
}

---@type NeotreeConfig.event_handler[]
-- TODO: Move event_handler examples to wiki
-- See http://TODO/make/wiki/page for examples.
config.event_handlers = {}

-- config.event_handlers = {
--   {
--     event = "before_render",
--     handler = function(state)
--       -- add something to the state that can be used by custom components
--     end,
--   },
--   {
--     event = "file_opened",
--     handler = function(file_path)
--       --auto close
--       require("neo-tree.command").execute({ action = "close" })
--     end,
--   },
--   {
--     event = "file_opened",
--     handler = function(file_path)
--       --clear search after opening a file
--       require("neo-tree.sources.filesystem").reset_search()
--     end,
--   },
--   {
--     event = "file_renamed",
--     handler = function(args)
--       -- fix references to file
--       print(args.source, " renamed to ", args.destination)
--     end,
--   },
--   {
--     event = "file_moved",
--     handler = function(args)
--       -- fix references to file
--       print(args.source, " moved to ", args.destination)
--     end,
--   },
--   {
--     event = "neo_tree_buffer_enter",
--     handler = function()
--       vim.cmd("highlight! Cursor blend=100")
--     end,
--   },
--   {
--     event = "neo_tree_buffer_leave",
--     handler = function()
--       vim.cmd("highlight! Cursor guibg=#5f87af blend=0")
--     end,
--   },
--   {
--     event = "neo_tree_window_before_open",
--     handler = function(args)
--       print("neo_tree_window_before_open", vim.inspect(args))
--     end,
--   },
--   {
--     event = "neo_tree_window_after_open",
--     handler = function(args)
--       vim.cmd("wincmd =")
--     end,
--   },
--   {
--     event = "neo_tree_window_before_close",
--     handler = function(args)
--       print("neo_tree_window_before_close", vim.inspect(args))
--     end,
--   },
--   {
--     event = "neo_tree_window_after_close",
--     handler = function(args)
--       vim.cmd("wincmd =")
--     end,
--   },
-- }

-- TODO: Add this hack to wiki.
-- kinds = {
--   -- ccls
--   -- TypeAlias = { icon = ' ', hl = 'Type' },
--   -- Parameter = { icon = ' ', hl = '@parameter' },
--   -- StaticMethod = { icon = '󰠄 ', hl = 'Function' },
--   -- Macro = { icon = ' ', hl = 'Macro' },
-- }
-- custom_kinds = {
--   -- ccls
--   [252] = 'TypeAlias',
--   [253] = 'Parameter',
--   [254] = 'StaticMethod',
--   [255] = 'Macro',
-- }

return config
