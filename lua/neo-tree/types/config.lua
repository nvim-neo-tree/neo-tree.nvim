---@class NeotreeConfig
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
---@field git_status_async_options NeotreeConfig.git_status_async_options|nil ({}) These options are for people with VERY large git repos
---@field hide_root_node boolean|nil (false) Hide the root node.
---IF the root node is hidden, keep the indentation anyhow.
---This is needed if you use expanders because they render in the indent.
---@field retain_hidden_root_indent boolean|nil (false)
---@field log_level NeotreeConfig.log_level|nil ("info") "trace", "debug", "info", "warn", "error", "fatal"
---@field log_to_file boolean|NeotreePathString|nil (false) true, false, "/path/to/file.log", use :NeoTreeLogs to show the file
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
---@field source_selector NeotreeConfig.source_selector|nil -- provides clickable tabs to switch between sources.
---@field default_component_configs NeotreeConfig.components|nil
-- The renderer section provides the renderers that will be used to render the tree.
-- The first level is the node type.
-- For each node type, you can specify a list of components to render.
-- Components are rendered in the order they are specified.
-- The first field in each component is the name of the function to call.
-- The rest of the fields are passed to the function as the "config" argument.
---@field renderers NeotreeConfig.renderers|nil
---@field commands NeotreeConfig.mappings|nil
---@field window NeotreeConfig.window|nil
---@field filesystem NeotreeConfig.filesystem|nil
---@field buffers NeotreeConfig.buffers|nil
---@field git_status NeotreeConfig.git_status|nil
---@field document_symbols NeotreeConfig.document_symbols|nil
---@field nesting_rules table<string, NeotreeConfig.nesting_rule>|nil
---@field event_handlers NeotreeConfig.event_handler[]|nil

---@class NeotreeConfig.git_status_async_options
---@field batch_size integer|nil (1000) how many lines of git status results to process at a time
---@field batch_delay integer|nil (10) delay in ms between batches. Spreads out the workload to let other processes run.
---How many lines of git status results to process. Anything after this will be dropped.
---Anything before this will be used. The last items to be processed are the untracked files.
---@field max_lines integer|nil (10000)

---source_selector provides clickable tabs to switch between sources.
---@class NeotreeConfig.source_selector
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
---@field highlight_tab NeotreeConfig.highlight|nil ("NeoTreeTabInactive")
---@field highlight_tab_active NeotreeConfig.highlight|nil ("NeoTreeTabActive")
---@field highlight_background NeotreeConfig.highlight|nil ("NeoTreeTabInactive")
---@field highlight_separator NeotreeConfig.highlight|nil ("NeoTreeTabSeparatorInactive")
---@field highlight_separator_active NeotreeConfig.highlight|nil ("NeoTreeTabSeparatorActive")

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

---@class NeotreeConfig.components
---@field container NeotreeConfig.components.container|nil
---@field diagnostics NeotreeConfig.components.diagnostics|nil
---@field indent NeotreeConfig.components.indent|nil
---@field icon NeotreeConfig.components.icon|nil
---@field modified NeotreeConfig.components.modified|nil
---@field name NeotreeConfig.components.name|nil
---@field git_status NeotreeConfig.components.git_status|nil
---@field [NeotreeConfig.components.enum] NeotreeConfig.components.base|nil

---@alias NeotreeConfig.components.enum
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

---@class NeotreeConfig.components.base : { [1]: NeotreeConfig.components.enum }
---@field enabled boolean|nil (true) You can set `enabled = false` for each of them individually
---@field required_width integer|nil (64) min width of window required to show this column
---@field zindex integer|nil
---@field content NeotreeConfig.components.base[]|nil

---@class NeotreeConfig.components.container : NeotreeConfig.components.base
---@field enable_character_fade boolean|nil (true)
---@field width NeotreeConfig.wh|nil ("100%")
---@field right_padding integer|nil (0)

---@class NeotreeConfig.components.diagnostics : NeotreeConfig.components.base
---@field symbols { [NeotreeConfig.diagnostics_keys]: string }|nil
---@field highlights { [NeotreeConfig.diagnostics_keys]: NeotreeConfig.highlight }|nil

---@class NeotreeConfig.components.indent : NeotreeConfig.components.base
---@field indent_size integer|nil (2)
---@field padding integer|nil (1)
---@field with_markers boolean|nil (true) indent guides
---@field indent_marker string|nil ("│")
---@field last_indent_marker string|nil ("└")
---@field highlight NeotreeConfig.highlight|nil ("NeoTreeIndentMarker")
---@field with_expanders boolean|nil (nil) expander config, needed for nesting files if nil and file nesting is enabled, will enable expanders
---@field expander_collapsed string|nil ("")
---@field expander_expanded string|nil ("")
---@field expander_highlight NeotreeConfig.highlight|nil ("NeoTreeExpander")

---@class NeotreeConfig.components.icon : NeotreeConfig.components.base
---@field folder_closed string|nil ("")
---@field folder_open string|nil ("")
---@field folder_empty string|nil ("󰉖")
---@field folder_empty_open string|nil ("󰷏")
---@field default string|nil ("*") # Used as a fallback.
---@field highlight NeotreeConfig.highlight|nil ("NeoTreeFileIcon") # Used as a fallback.

---@class NeotreeConfig.components.modified : NeotreeConfig.components.base
---@field symbol string|nil ("[+] ")
---@field highlight NeotreeConfig.highlight|nil ("NeoTreeModified")

---@class NeotreeConfig.components.name : NeotreeConfig.components.base
---@field trailing_slash boolean|nil (false)
---@field highlight_opened_files NeotreeConfig.components.name.highlight_opened_files|nil (false) Requires `enable_opened_markers = true`.
---@field use_git_status_colors boolean|nil (true)
---@field highlight NeotreeConfig.highlight|nil ("NeoTreeFileName")

---@alias NeotreeConfig.components.name.highlight_opened_files
---|true  # Hightlight only loaded files
---|false # Do nothing
---|"all" # Highlight both loaded and unloaded files

---@class NeotreeConfig.components.git_status : NeotreeConfig.components.base
---@field symbols { [NeotreeConfig.components.git_status.symbol_change|NeotreeConfig.components.git_status.symbol_status]: string }|nil
---@field align NeotreeConfig.components.align|nil ("right")

---@alias NeotreeConfig.components.git_status.symbol_change "added" | "deleted" | "modified" | "renamed"
---@alias NeotreeConfig.components.git_status.symbol_status "untracked" | "ignored" | "unstaged" | "staged" | "conflict"

---@alias NeotreeConfig.renderers { [string]: NeotreeConfig.components.base[] }

---@class NeotreeConfig.window
---@field position NeotreeWindowPosition|nil ("left") left, right, top, bottom, float, current
---@field width NeotreeConfig.wh|nil (40) applies to left and right positions
---@field height NeotreeConfig.wh|nil (15) applies to top and bottom positions
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
---@field mappings NeotreeConfig.mappings|nil
---@field fuzzy_finder_mappings NeotreeConfig.mappings|nil ({}) define keymaps for filter popup window in fuzzy_finder_mode

---@class NeotreeConfig.mapping_options
---@field nowait boolean|nil (true) disable `nowait` if you have existing combos starting with this char that you want to use
---@field noremap boolean|nil (true)

---@alias NeotreeConfig.mapping_table { [1]: string, config: table<string, any> } | NeotreeConfig.mapping_options
---@alias NeotreeConfig.mapping_function fun(state: NeotreeState)
---@alias NeotreeConfig.mappings table<string, string | NeotreeConfig.mapping_table | NeotreeConfig.mapping_function>

---@class NeotreeConfig.source_config
---@field name string
---@field display_name string
---@field window NeotreeConfig.window|nil
---@field renderers NeotreeConfig.renderers|nil
---@field commands NeotreeConfig.mappings|nil
---@field components NeotreeConfig.components|nil

---@class NeotreeConfig.filesystem : NeotreeConfig.source_config
---@field async_directory_scan NeotreeConfig.filesystem.async_directory_scan|nil ("auto")
---@field scan_mode NeotreeConfig.filesystem.scan_mode|nil ("shallow")
---@field bind_to_cwd boolean|nil (true) true creates a 2-way binding between vim's cwd and neo-tree's root
---@field cwd_target NeotreeConfig.filesystem.cwd_target|nil ({})
---check gitignore status for files/directories when searching
---setting this to `false` will speed up searches, but gitignored
---items won't be marked if they are visible.
---@field check_gitignore_in_search boolean|nil (true)
---`false` means it only searches the tail of a path.
---`true` will change the filter into a full path search with space as an implicit ".*",
---so `fi init` will match: `./sources/filesystem/init.lua`
---@field find_by_full_path_words boolean|nil (false)
---@field find_command string|nil (nil) this is determined automatically, you probably don't need to set it
---@field find_args NeotreeConfig.filesystem.find_args|nil (nil) List or a func that returns args for `find_command`
---@field group_empty_dirs boolean|nil (false) when true, empty folders will be grouped together
---@field search_limit integer|nil (50) max number of search results when using filters
---@field follow_current_file NeotreeConfig.filesystem.follow_current_file|nil
---@field hijack_netrw_behavior NeotreeConfig.filesystem.hijack_netrw_behavior|nil ("open_default")
---@field use_libuv_file_watcher boolean|nil (false) This will use the OS level file watchers to detect changes instead of relying on nvim autocmd events.

---@alias NeotreeConfig.filesystem.async_directory_scan
---|"auto"   # means refreshes are async, but it's synchronous when called from the Neotree commands.
---|"always" # means directory scans are always async.
---|"never"  # means directory scans are never async.

---@alias NeotreeConfig.filesystem.scan_mode
---|"shallow" # Don't scan into directories to detect possible empty directory a priori
---|"deep"    # Scan into directories to detect empty or grouped empty directories a priori.

---@class NeotreeConfig.filesystem.cwd_target
---@field sidebar string|nil ("tab") sidebar is when position = left or right
---@field current string|nil ("window") current is when position = current

---@class NeotreeConfig.filesystem.filtered_items
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

---@class NeotreeConfig.filesystem.follow_current_file
---This will find and focus the file in the active buffer every time
---the current file is changed while the tree is open.
---@field enabled boolean|nil (false)
---@field leave_dirs_open boolean|nil (false) `false` closes auto expanded dirs, such as with `:Neotree reveal`

---@alias NeotreeConfig.filesystem.hijack_netrw_behavior
---|"open_default" # netrw disabled, opening a directory opens neo-tree in whatever position is specified in window.position
---|"open_current" # netrw disabled, opening a directory opens within the window like netrw would, regardless of window.position
---|"disabled"     # netrw left alone, neo-tree does not handle opening dirs

---@alias NeotreeConfig.filesystem.find_args
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

---@class NeotreeConfig.buffers : NeotreeConfig.source_config
---@field bind_to_cwd boolean|nil (true) true creates a 2-way binding between vim's cwd and neo-tree's root
---@field group_empty_dirs boolean|nil (false) when true, empty folders will be grouped together
---@field follow_current_file NeotreeConfig.filesystem.follow_current_file|nil
---When working with sessions, for example, restored but unfocused buffers
---are mark as "unloaded". Turn this on to view these unloaded buffer.
---@field show_unloaded boolean|nil (false)
---@field terminals_first boolean|nil (false) when true, terminals will be listed before file buffers

---@class NeotreeConfig.document_symbols.kinds : NeotreeConfig.source_config
---@field icon string|nil
---@field hl NeotreeConfig.highlight|nil

---@class NeotreeConfig.document_symbols : NeotreeConfig.source_config
---@field follow_cursor boolean|nil (false)
---@field client_filters string|nil ("first")
---@field kinds table<string, NeotreeConfig.document_symbols.kinds>|nil
---@field custom_kinds table<integer|string, string|NeotreeConfig.document_symbols.kinds>|nil

---@class NeotreeConfig.git_status : NeotreeConfig.source_config

---@class NeotreeConfig.nesting_rule
---@field pattern string # Filename match regex pattern
---@field ignore_case boolean|nil # Whether to Match `files` names case insensitive
---@field files string[] # List of file names that will be nested under `pattern` file.

---@alias NeotreeConfig.event_handler
---|NeotreeConfig.event_handler.base
---|NeotreeConfig.event_handler.file_path
---|NeotreeConfig.event_handler.file_operation
---|NeotreeConfig.event_handler.state
---|NeotreeConfig.event_handler.buffer
---|NeotreeConfig.event_handler.window

---@class NeotreeConfig.event_handler.base
---@field id string|nil
---@field cancelled boolean|nil
---@field once boolean|nil
---@field event NeotreeEventEnum
---@field handler fun(args: NeotreeAutocmdArg): any

---@alias NeotreeConfig.event_handler.file_path.enum
---|"file_opened"
---@class NeotreeConfig.event_handler.file_path : NeotreeConfig.event_handler.base
---@field event NeotreeConfig.event_handler.file_path.enum
---@field handler fun(args: { source: string, destination: string }): any

---@alias NeotreeConfig.event_handler.file_operation.enum
---|"file_renamed"
---|"file_moved"
---@class NeotreeConfig.event_handler.file_operation : NeotreeConfig.event_handler.base
---@field event NeotreeConfig.event_handler.file_operation.enum
---@field handler fun(file_operation: string): any

---@alias NeotreeConfig.event_handler.state.enum
---|"before_render"
---@class NeotreeConfig.event_handler.state : NeotreeConfig.event_handler.base
---@field event NeotreeConfig.event_handler.state.enum
---@field handler fun(state: NeotreeState): any

---@alias NeotreeConfig.event_handler.buffer.enum
---|"neo_tree_buffer_enter"
---|"neo_tree_buffer_leave"
---@class NeotreeConfig.event_handler.buffer : NeotreeConfig.event_handler.base
---@field event NeotreeConfig.event_handler.buffer.enum
---@field handler fun(): any

---@alias NeotreeConfig.event_handler.window.enum
---|"neo_tree_window_before_open"
---|"neo_tree_window_after_open"
---|"neo_tree_window_before_close"
---|"neo_tree_window_after_close"
---@class NeotreeConfig.event_handler.window : NeotreeConfig.event_handler.base
---@field event NeotreeConfig.event_handler.window.enum
---@field handler fun(args: NeotreeConfig.event_handler.window.args): any
---
---@class NeotreeConfig.event_handler.window.args
---@field position NeotreeWindowPosition
---@field source string
---@field tabnr integer|nil
---@field tabid integer|nil
