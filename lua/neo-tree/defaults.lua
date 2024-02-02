---@class NeotreeTypes.config
---If a user has a sources list it will replace this one.
---Only sources listed here will be loaded.
---You can also add an external source by adding it's name to this list.
---The name used here must be the same name you would use in a require() call.
---Defaults:
---- "filesystem",
---- "buffers",
---- "git_status",
---@field sources string[]|nil
---@field add_blank_line_at_top boolean|nil (false) Add a blank line at the top of the tree.
---@field auto_clean_after_session_restore boolean|nil (false) Automatically clean up broken neo-tree buffers saved in sessions
---@field close_if_last_window boolean|nil (false) Close Neo-tree if it is the last window left in the tab
---@field default_source string|nil ("filesystem") you can choose a specific source `last` here which indicates the last used source
---@field enable_diagnostics boolean|nil (true)
---@field enable_git_status boolean|nil (true)
---@field enable_modified_markers boolean|nil (true) Show markers for files with unsaved changes.
---@field enable_opened_markers boolean|nil (true) Enable tracking of opened files. Required for `components.name.highlight_opened_files`
---@field enable_refresh_on_write boolean|nil (true) Refresh the tree when a file is written. Only used if `use_libuv_file_watcher` is false.
---@field enable_cursor_hijack boolean|nil (false) If enabled neotree will keep the cursor on the first letter of the filename when moving in the tree.
---@field enable_normal_mode_for_inputs boolean|nil (false) Enable normal mode for input dialogs.
---@field git_status_async boolean|nil (true)
---@field git_status_async_options NeotreeTypes.config.git_status_async_options|nil ({}) These options are for people with VERY large git repos
---@field hide_root_node boolean|nil (false) Hide the root node.
---IF the root node is hidden, keep the indentation anyhow.
---This is needed if you use expanders because they render in the indent.
---@field retain_hidden_root_indent boolean|nil (false)
---@field log_level string|nil ("info") "trace", "debug", "info", "warn", "error", "fatal"
---@field log_to_file boolean|nil (false) true, false, "/path/to/file.log", use :NeoTreeLogs to show the file
---@field open_files_in_last_window boolean|nil (true) false = open files in top left window
---@field open_files_do_not_replace_types string[]|nil ({ "terminal", "Trouble", "qf", "edgy" }) when opening files, do not use windows containing these filetypes or buftypes
---popup_border_style is for input and confirmation dialogs.
---Configurtaion of floating window is done in the individual source sections.
---"NC" is a special style that works well with NormalNC set
---@field popup_border_style string|nil ("NC") "double", "none", "rounded", "shadow", "single" or "solid"
---set to -1 to disable the resize timer entirely
---this will speed up to 50 ms for 1 second following a resize
---@field resize_timer_interval integer|nil (500) in ms, needed for containers to redraw right aligned and faded content
---@field sort_case_insensitive boolean|nil (false) used when sorting files and directories in the tree
---@field sort_function NeotreeTypes.sort_function|nil (nil) uses a custom function for sorting files and directories in the tree
---@field use_popups_for_input boolean|nil (true) If false, inputs will use vim.ui.input() instead of custom floats.
---@field use_default_mappings boolean|nil (true)
---@field source_selector NeotreeTypes.config.source_selector|nil -- provides clickable tabs to switch between sources.
---@field default_component_configs NeotreeTypes.config.components|nil
-- The renderer section provides the renderers that will be used to render the tree.
-- The first level is the node type.
-- For each node type, you can specify a list of components to render.
-- Components are rendered in the order they are specified.
-- The first field in each component is the name of the function to call.
-- The rest of the fields are passed to the function as the "config" argument.
---@field renderers NeotreeTypes.config.renderers|nil
---@field commands NeotreeTypes.config.mappings|nil
---@field window NeotreeTypes.config.window|nil
---@field filesystem NeotreeTypes.config.filesystem|nil
---@field buffers NeotreeTypes.config.buffers|nil
---@field git_status NeotreeTypes.config.git_status|nil
---@field document_symbols NeotreeTypes.config.document_symbols|nil
---@field nesting_rules table<string, NeotreeTypes.config.nesting_rule>|nil
---@field event_handlers NeotreeTypes.config.event_handler[]|nil

---@alias NeotreeTypes.sort_function fun(a: NeotreeTypes.node, b: NeotreeTypes.node): boolean
---@alias NeotreeTypes.config.highlight string # Name of a highlight group
---@alias NeotreeTypes.config.wh integer|string|nil
---@alias NeotreeTypes.config.diagnostics_keys "hint"|"info"|"warn"|"error"
---@alias NeotreeTypes.config.components.align "left"|"right"

---@class NeotreeTypes.config.git_status_async_options
---@field batch_size integer|nil (1000) how many lines of git status results to process at a time
---@field batch_delay integer|nil (10) delay in ms between batches. Spreads out the workload to let other processes run.
---How many lines of git status results to process. Anything after this will be dropped.
---Anything before this will be used. The last items to be processed are the untracked files.
---@field max_lines integer|nil (10000)

---source_selector provides clickable tabs to switch between sources.
---@class NeotreeTypes.config.source_selector
---@field winbar boolean|nil (false) toggle to show selector on winbar
---@field statusline boolean|nil (false) toggle to show selector on statusline
---@field show_scrolled_off_parent_node boolean|nil (false) this will replace the tabs with the parent path of the top visible node when scrolled down.
---@field sources { source: string }[]|nil
---@field content_layout NeotreeTypes.selector.content_layout|nil ("start") # only with `tabs_layout` = "equal", "focus"
---@field tabs_layout NeotreeTypes.selector.tabs_layout|nil ("equal") start, end, center, equal, focus
---@field truncation_character string|nil ("…") character to use when truncating the tab label
---@field tabs_min_width integer|nil (nil) if int padding is added based on `content_layout`
---@field tabs_max_width integer|nil (nil) this will truncate text even if `text_trunc_to_fit = false`
---Can be int or table
---padding = 2 -> { left = 2, right = 2 },
---padding = { left = 2, right = 0 },
---@field padding NeotreeTypes.selector.padding|nil (0)
---Can be string or table, see below
-- separator = { left = "▏", right= "▕" },
-- separator = { left = "/", right = "\\", override = nil },     -- |/  a  \/  b  \/  c  \...
-- separator = { left = "/", right = "\\", override = "right" }, -- |/  a  \  b  \  c  \...
-- separator = { left = "/", right = "\\", override = "left" },  -- |/  a  /  b  /  c  /...
-- separator = { left = "/", right = "\\", override = "active" },-- |/  a  / b:active \  c  \...
-- separator = "|",                                              -- ||  a  |  b  |  c  |...
---@field separator NeotreeTypes.selector.separator|nil ("▕")
---@field separator_active NeotreeTypes.selector.separator|nil (nil) set separators around the active tab. nil falls back to `source_selector.separator`
----true  : |/    a    \/    b    \/    c    \|
----false : |     a    \/    b    \/    c     |
---@field show_separator_on_edge boolean|nil (false)
---@field highlight_tab NeotreeTypes.config.highlight|nil ("NeoTreeTabInactive")
---@field highlight_tab_active NeotreeTypes.config.highlight|nil ("NeoTreeTabActive")
---@field highlight_background NeotreeTypes.config.highlight|nil ("NeoTreeTabInactive")
---@field highlight_separator NeotreeTypes.config.highlight|nil ("NeoTreeTabSeparatorInactive")
---@field highlight_separator_active NeotreeTypes.config.highlight|nil ("NeoTreeTabSeparatorActive")

---@alias NeotreeTypes.selector.content_layout
---|"start"  : |/ 󰓩 bufname     \/...
---|"end"    : |/     󰓩 bufname \/...
---|"center" : |/   󰓩 bufname   \/...

---@alias NeotreeTypes.selector.tabs_layout
---|"start"  : |/  a  \/  b  \/  c  \            |
---|"end"    : |            /  a  \/  b  \/  c  \|
---|"center" : |      /  a  \/  b  \/  c  \      |
---|"equal"  : |/    a    \/    b    \/    c    \|
---|"active" : |/  focused tab    \/  b  \/  c  \|

---@alias NeotreeTypes.selector.padding integer|NeotreeTypes.selector.padding.table|nil
---@alias NeotreeTypes.selector.padding.table { left: integer|nil, right: integer|nil }

---@alias NeotreeTypes.selector.separator string|NeotreeTypes.selector.separator.table|nil
---@alias NeotreeTypes.selector.separator.table { left: string|nil, right: string|nil, override: string|nil }

---@class NeotreeTypes.config.components
---@field container NeotreeTypes.config.components.container|nil
---@field diagnostics NeotreeTypes.config.components.diagnostics|nil
---@field indent NeotreeTypes.config.components.indent|nil
---@field icon NeotreeTypes.config.components.icon|nil
---@field modified NeotreeTypes.config.components.modified|nil
---@field name NeotreeTypes.config.components.name|nil
---@field git_status NeotreeTypes.config.components.git_status|nil
---@field [NeotreeTypes.config.components.enum] NeotreeTypes.config.components.base|nil

---@alias NeotreeTypes.config.components.enum
---|"container"
---|"diagnostics"
---|"indent"
---|"icon"
---|"modified"
---|"name"
---|"git_status"
---|"file_size"
---|"type"
---|"last_modified"
---|"created"
---|"symlink_target"
---|"bufnr"
---|"clipboard"
---|"current_filter"
---|"kind_icon"
---|"kind_name"

---@class NeotreeTypes.config.components.base : { [1]: NeotreeTypes.config.components.enum }
---@field enabled boolean|nil (true) You can set `enabled = false` for each of them individually
---@field required_width integer|nil (64) min width of window required to show this column
---@field zindex integer|nil
---@field content NeotreeTypes.config.components.base[]|nil

---@class NeotreeTypes.config.components.container : NeotreeTypes.config.components.base
---@field enable_character_fade boolean|nil (true)
---@field width NeotreeTypes.config.wh|nil ("100%")
---@field right_padding integer|nil (0)

---@class NeotreeTypes.config.components.diagnostics : NeotreeTypes.config.components.base
---@field symbols { [NeotreeTypes.config.diagnostics_keys]: string }|nil
---@field highlights { [NeotreeTypes.config.diagnostics_keys]: NeotreeTypes.config.highlight }|nil

---@class NeotreeTypes.config.components.indent : NeotreeTypes.config.components.base
---@field indent_size integer|nil (2)
---@field padding integer|nil (1)
---@field with_markers boolean|nil (true) indent guides
---@field indent_marker string|nil ("│")
---@field last_indent_marker string|nil ("└")
---@field highlight NeotreeTypes.config.highlight|nil ("NeoTreeIndentMarker")
---@field with_expanders boolean|nil (nil) expander config, needed for nesting files if nil and file nesting is enabled, will enable expanders
---@field expander_collapsed string|nil ("")
---@field expander_expanded string|nil ("")
---@field expander_highlight NeotreeTypes.config.highlight|nil ("NeoTreeExpander")

---@class NeotreeTypes.config.components.icon : NeotreeTypes.config.components.base
---@field folder_closed string|nil ("")
---@field folder_open string|nil ("")
---@field folder_empty string|nil ("󰉖")
---@field folder_empty_open string|nil ("󰷏")
---@field default string|nil ("*") # Used as a fallback.
---@field highlight NeotreeTypes.config.highlight|nil ("NeoTreeFileIcon") # Used as a fallback.

---@class NeotreeTypes.config.components.modified : NeotreeTypes.config.components.base
---@field symbol string|nil ("[+] ")
---@field highlight NeotreeTypes.config.highlight|nil ("NeoTreeModified")

---@class NeotreeTypes.config.components.name : NeotreeTypes.config.components.base
---@field trailing_slash boolean|nil (false)
---@field highlight_opened_files NeotreeTypes.config.components.name.highlight_opened_files|nil (false) Requires `enable_opened_markers = true`.
---@field use_git_status_colors boolean|nil (true)
---@field highlight NeotreeTypes.config.highlight|nil ("NeoTreeFileName")

---@alias NeotreeTypes.config.components.name.highlight_opened_files
---|true  # Hightlight only loaded files
---|false # Do nothing
---|"all" # Highlight both loaded and unloaded files

---@class NeotreeTypes.config.components.git_status : NeotreeTypes.config.components.base
---@field symbols { [NeotreeTypes.config.components.git_status.symbol_change|NeotreeTypes.config.components.git_status.symbol_status]: string }|nil
---@field align NeotreeTypes.config.components.align|nil ("right")

---@alias NeotreeTypes.config.components.git_status.symbol_change "added" | "deleted" | "modified" | "renamed"
---@alias NeotreeTypes.config.components.git_status.symbol_status "untracked" | "ignored" | "unstaged" | "staged" | "conflict"

---@alias NeotreeTypes.config.renderers { [string]: NeotreeTypes.config.components.base[] }

---@alias NeotreeTypes.config.window.position
---|"left"
---|"right"
---|"top"
---|"bottom"
---|"float"
---|"current"

---@class NeotreeTypes.config.window
---@field position NeotreeTypes.config.window.position|nil ("left") left, right, top, bottom, float, current
---@field width NeotreeTypes.config.wh|nil (40) applies to left and right positions
---@field height NeotreeTypes.config.wh|nil (15) applies to top and bottom positions
---@field auto_expand_width boolean|nil (false) expand the window when file exceeds the window width. does not work with position = "float"
---@field same_level boolean|nil (false) Create and paste/move files/directories on the same level as the directory under cursor (as opposed to within the directory under cursor).
---Affects how nodes get inserted into the tree during creation/pasting/moving of files if the node under the cursor is a directory:
----"child":   Insert nodes as children of the directory under cursor.
----"sibling": Insert nodes  as siblings of the directory under cursor.
---@field insert_as '"child"'|'"sibling"'|nil ("child")
---@field mapping_options table|nil # default mapping options passed to `vim.keymap.set`.
---Options passed to `NuiPopup`.
---Default:
---  size = {
---    height = "80%",
---    width = "50%",
---  },
---  position = "50%", -- 50% means center it
---@field popup nui_popup_options|nil
---Mappings for tree window. See `:h neo-tree-mappings` for a list of built-in commands.
---@field mappings NeotreeTypes.config.mappings|nil
---@field fuzzy_finder_mappings NeotreeTypes.config.mappings|nil ({}) define keymaps for filter popup window in fuzzy_finder_mode

---@class NeotreeTypes.config.mapping_options
---@field nowait boolean|nil (true) disable `nowait` if you have existing combos starting with this char that you want to use
---@field noremap boolean|nil (true)

---@alias NeotreeTypes.config.mapping_table { [1]: string, config: table<string, any> } | NeotreeTypes.config.mapping_options
---@alias NeotreeTypes.config.mapping_function fun(state: NeotreeTypes.state)
---@alias NeotreeTypes.config.mappings table<string, string | NeotreeTypes.config.mapping_table | NeotreeTypes.config.mapping_function>

---@class NeotreeTypes.config.filesystem
---@field window NeotreeTypes.config.window|nil
---@field renderers NeotreeTypes.config.renderers|nil
---@field async_directory_scan NeotreeTypes.config.filesystem.async_directory_scan|nil ("auto")
---@field scan_mode NeotreeTypes.config.filesystem.scan_mode|nil ("shallow")
---@field bind_to_cwd boolean|nil (true) true creates a 2-way binding between vim's cwd and neo-tree's root
---@field cwd_target NeotreeTypes.config.filesystem.cwd_target|nil ({})
---check gitignore status for files/directories when searching
---setting this to `false` will speed up searches, but gitignored
---items won't be marked if they are visible.
---@field check_gitignore_in_search boolean|nil (true)
---`false` means it only searches the tail of a path.
---`true` will change the filter into a full path search with space as an implicit ".*",
---so `fi init` will match: `./sources/filesystem/init.lua`
---@field find_by_full_path_words boolean|nil (false)
---@field find_command string|nil (nil) this is determined automatically, you probably don't need to set it
---@field find_args NeotreeTypes.config.filesystem.find_args|nil (nil) List or a func that returns args for `find_command`
---@field group_empty_dirs boolean|nil (false) when true, empty folders will be grouped together
---@field search_limit integer|nil (50) max number of search results when using filters
---@field follow_current_file NeotreeTypes.config.filesystem.follow_current_file|nil
---@field hijack_netrw_behavior NeotreeTypes.config.filesystem.hijack_netrw_behavior|nil ("open_default")
---@field use_libuv_file_watcher boolean|nil (false) This will use the OS level file watchers to detect changes instead of relying on nvim autocmd events.

---@alias NeotreeTypes.config.filesystem.async_directory_scan
---|"auto"   # means refreshes are async, but it's synchronous when called from the Neotree commands.
---|"always" # means directory scans are always async.
---|"never"  # means directory scans are never async.

---@alias NeotreeTypes.config.filesystem.scan_mode
---|"shallow" # Don't scan into directories to detect possible empty directory a priori
---|"deep"    # Scan into directories to detect empty or grouped empty directories a priori.

---@class NeotreeTypes.config.filesystem.cwd_target
---@field sidebar string|nil ("tab") sidebar is when position = left or right
---@field current string|nil ("window") current is when position = current

---@class NeotreeTypes.config.filesystem.filtered_items
---@field visible boolean|nil (false) when true, they will just be displayed differently than normal items
---@field force_visible_in_empty_folder boolean|nil (false) when true, hidden files will be shown if the root folder is otherwise empty
---@field show_hidden_count boolean|nil (true) when true, the number of hidden items in each folder will be shown as the last entry
---@field hide_dotfiles boolean|nil (true)
---@field hide_gitignored boolean|nil (true)
---@field hide_hidden boolean|nil (true) only works on Windows for hidden files/directories
---@field hide_by_name string[]|nil ({ ".DS_Store", "thumbs.db" })
---@field hide_by_pattern string[]|nil ({}) uses glob style patterns
---@field always_show string[]|nil ({}) remains visible even if other settings would normally hide it
---@field never_show string[]|nil ({}) remains hidden even if visible is toggled to true, this overrides always_show
---@field never_show_by_pattern string[]|nil ({}) uses glob style patterns

---@class NeotreeTypes.config.filesystem.follow_current_file
---This will find and focus the file in the active buffer every time
---the current file is changed while the tree is open.
---@field enabled boolean|nil (false)
---@field leave_dirs_open boolean|nil (false) `false` closes auto expanded dirs, such as with `:Neotree reveal`

---@alias NeotreeTypes.config.filesystem.hijack_netrw_behavior
---|"open_default" # netrw disabled, opening a directory opens neo-tree in whatever position is specified in window.position
---|"open_current" # netrw disabled, opening a directory opens within the window like netrw would, regardless of window.position
---|"disabled"     # netrw left alone, neo-tree does not handle opening dirs

---@alias NeotreeTypes.config.filesystem.find_args
---You can specify extra args to pass to the find command.
---```lua
---find_args = {
---  fd = {
---    "--exclude", ".git",
---    "--exclude",  "node_modules"
---  }
---}
---```
---|table<string, string[]>
---or use a function instead of list of strings
---```lua
---find_args = function(cmd, path, search_term, args)
---  if cmd == "fd" then
---    table.insert(args, "--hidden")
---    -- ...
---  end
---  return args
---end,
---```
---|fun(cmd: string, path: string, search_term: string, args: string[]): string[])

---@class NeotreeTypes.config.buffers
---@field window NeotreeTypes.config.window|nil
---@field renderers NeotreeTypes.config.renderers|nil
---@field bind_to_cwd boolean|nil (true) true creates a 2-way binding between vim's cwd and neo-tree's root
---@field group_empty_dirs boolean|nil (false) when true, empty folders will be grouped together
---@field follow_current_file NeotreeTypes.config.filesystem.follow_current_file|nil
---When working with sessions, for example, restored but unfocused buffers
---are mark as "unloaded". Turn this on to view these unloaded buffer.
---@field show_unloaded boolean|nil (false)
---@field terminals_first boolean|nil (false) when true, terminals will be listed before file buffers

---@class NeotreeTypes.config.document_symbols.kinds
---@field icon string|nil
---@field hl NeotreeTypes.config.highlight|nil

---@class NeotreeTypes.config.document_symbols
---@field window NeotreeTypes.config.window|nil
---@field renderers NeotreeTypes.config.renderers|nil
---@field follow_cursor boolean|nil (false)
---@field client_filters string|nil ("first")
---@field kinds table<string, NeotreeTypes.config.document_symbols.kinds>|nil
---@field custom_kinds table<integer|string, string|NeotreeTypes.config.document_symbols.kinds>|nil

---@class NeotreeTypes.config.git_status
---@field window NeotreeTypes.config.window|nil
---@field renderers NeotreeTypes.config.renderers|nil

---@class NeotreeTypes.config.nesting_rule
---@field pattern string # Filename match regex pattern
---@field ignore_case boolean|nil # Whether to Match `files` names case insensitive
---@field files string[] # List of file names that will be nested under `pattern` file.

---@alias NeotreeTypes.config.event_handler
---|NeotreeTypes.config.event_handler.file_path
---|NeotreeTypes.config.event_handler.file_operation
---|NeotreeTypes.config.event_handler.state
---|NeotreeTypes.config.event_handler.buffer
---|NeotreeTypes.config.event_handler.window

---@alias NeotreeTypes.config.event_handler.file_path.enum
---|"file_opened"
---@class NeotreeTypes.config.event_handler.file_path
---@field event NeotreeTypes.config.event_handler.file_path.enum
---@field handler fun(args: { source: string, destination: string }): any

---@alias NeotreeTypes.config.event_handler.file_operation.enum
---|"file_renamed"
---|"file_moved"
---@class NeotreeTypes.config.event_handler.file_operation
---@field event NeotreeTypes.config.event_handler.file_operation.enum
---@field handler fun(file_operation: string): any

---@alias NeotreeTypes.config.event_handler.state.enum
---|"before_render"
---@class NeotreeTypes.config.event_handler.state
---@field event NeotreeTypes.config.event_handler.state.enum
---@field handler fun(state: NeotreeTypes.state): any

---@alias NeotreeTypes.config.event_handler.buffer.enum
---|"neo_tree_buffer_enter"
---|"neo_tree_buffer_leave"
---@class NeotreeTypes.config.event_handler.buffer
---@field event NeotreeTypes.config.event_handler.buffer.enum
---@field handler fun(): any

---@alias NeotreeTypes.config.event_handler.window.enum
---|"neo_tree_window_before_open"
---|"neo_tree_window_after_open"
---|"neo_tree_window_before_close"
---|"neo_tree_window_after_close"
---@class NeotreeTypes.config.event_handler.window
---@field event NeotreeTypes.config.event_handler.window.enum
---@field handler fun(args: NeotreeTypes.config.event_handler.window.args): any
---
---@class NeotreeTypes.config.event_handler.window.args
---@field position NeotreeTypes.config.window.position
---@field source string
---@field tabnr integer|nil
---@field tabid integer|nil

---@type NeotreeTypes.config
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

---@type NeotreeTypes.config.source_selector
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

---@type NeotreeTypes.config.components
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

---@type NeotreeTypes.config.renderers
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

---@type table<string, NeotreeTypes.config.nesting_rule>
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
---@type NeotreeTypes.config.mappings
config.commands = {}

---@type NeotreeTypes.config.window
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

---@type NeotreeTypes.config.filesystem
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

---@type NeotreeTypes.config.buffers
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

---@type NeotreeTypes.config.git_status
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

---@type NeotreeTypes.config.document_symbols
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

---@type NeotreeTypes.config.event_handler[]
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
