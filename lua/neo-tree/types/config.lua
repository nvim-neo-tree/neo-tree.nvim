---@meta

---@class neotree.Config.MappingOptions
---@field noremap boolean
---@field nowait boolean

---@class neotree.Config.Mapping : neotree.Config.MappingOptions
---@field [1] string
---@field nowait boolean?
---@field noremap boolean?
---@field config table?

---@alias neotree.Config.Window.Mappings table<string, string|neotree.Config.Mapping>

---@class neotree.Config.Source
---@field window neotree.Config.Source.Window
---@field renderers neotree.Config.Renderers[]?

---@class neotree.Config.Source.Window
---@field mappings neotree.Config.Window.Mappings

---@class neotree.Config.SourceSelector.Item
---@field source string
---@field padding? integer|{left:integer,right:integer}
---@field separator? string|{left:string,right:string, override?:string}

---@alias neotree.Config.SourceSelector.Separator.Override
---|"right"   # When right and left separators meet, only show the right one.
---|"left"    # When right and left separators meet, only show the left one.
---|"active"  # Only use the left separator on the left of the active tab, and only the right afterwards.
---|nil       # Show both separators.

---@class neotree.Config.SourceSelector.Separator
---@field left string
---@field right string
---@field override neotree.Config.SourceSelector.Separator.Override

---@class neotree.Config.SourceSelector
---@field winbar boolean
---@field statusline boolean
---@field show_scrolled_off_parent_node boolean
---@field sources neotree.Config.SourceSelector.Item[]
---@field content_layout string? "start"|"end"|"center"
---@field tabs_layout string? "equal"|"start"|"end"|"center"|"focus"
---@field truncation_character string
---@field tabs_min_width integer?
---@field tabs_max_width integer?
---@field padding integer?
---@field separator neotree.Config.SourceSelector.Separator?
---@field separator_active neotree.Config.SourceSelector.Separator?
---@field show_separator_on_edge boolean
---@field highlight_tab string
---@field highlight_tab_active string
---@field highlight_background string
---@field highlight_separator string
---@field highlight_separator_active string

---@class neotree.Config.GitStatusAsync
---@field batch_size integer
---@field batch_delay integer
---@field max_lines integer

---@class neotree.Config.Window.Size
---@field height string|number?
---@field width string|number?

---@class neotree.Config.Window.Popup
---@field title fun(state:table):string
---@field size neotree.Config.Window.Size
---@field border neotree.Config.BorderStyle

---@class neotree.Config.Window
---@field position string
---@field width integer
---@field height integer
---@field auto_expand_width boolean
---@field popup neotree.Config.Window.Popup
---@field same_level boolean
---@field insert_as "child"|"sibling"
---@field mapping_options neotree.Config.MappingOptions
---@field mappings table

---@alias neotree.Config.Cwd "tab"|"window"|"global"

---@class neotree.Config.Filesystem.CwdTarget
---@field sidebar neotree.Config.Cwd
---@field current neotree.Config.Cwd

---@class neotree.Config.Filesystem.FilteredItems
---@field visible boolean
---@field force_visible_in_empty_folder boolean
---@field show_hidden_count boolean
---@field hide_dotfiles boolean
---@field hide_gitignored boolean
---@field hide_hidden boolean
---@field hide_by_name string[]
---@field hide_by_pattern string[]
---@field always_show string[]
---@field always_show_by_pattern string[]
---@field never_show string[]
---@field never_show_by_pattern string[]

---@alias neotree.Config.Filesystem.FindArgsHandler fun(cmd:string, path:string, search_term:string, args:string[]):string[]

---@class neotree.Config.Filesystem.FollowCurrentFile
---@field enabled boolean
---@field leave_dirs_open boolean

---@alias neotree.Config.HijackNetrwBehavior
---|"open_default" # opening a directory opens neo-tree with the default window.position.
---|"open_current" # opening a directory opens neo-tree within the current window.
---|"disabled" # opening a directory opens neo-tree within the current window.

---@class neotree.Config.Filesystem : neotree.Config.Source
---@field async_directory_scan "auto"|"always"|"never"
---@field bind_to_cwd boolean
---@field cwd_target neotree.Config.Filesystem.CwdTarget
---@field check_gitignore_in_search boolean
---@field filtered_items neotree.Config.Filesystem.FilteredItems
---@field find_by_full_path_words boolean
---@field find_command string?
---@field find_args table<string, string[]>|neotree.Config.Filesystem.FindArgsHandler|nil
---@field group_empty_dirs boolean
---@field search_limit integer
---@field follow_current_file neotree.Config.Filesystem.FollowCurrentFile
---@field hijack_netrw_behavior neotree.Config.HijackNetrwBehavior
---@field use_libuv_file_watcher boolean

---@class neotree.Config.Buffers : neotree.Config.Source
---@field bind_to_cwd boolean
---@field follow_current_file neotree.Config.Filesystem.FollowCurrentFile
---@field group_empty_dirs boolean
---@field show_unloaded boolean
---@field terminals_first boolean

---@class neotree.Config.GitStatus : neotree.Config.Source

---@class neotree.Config.LspKindDisplay
---@field icon string
---@field hl string

---@class neotree.Config.DocumentSymbols : neotree.Config.Source
---@field follow_cursor boolean
---@field client_filters neotree.lsp.ClientFilter
---@field custom_kinds table<integer, string>
---@field kinds table<string, neotree.Config.LspKindDisplay>

---@class neotree.Config.EventHandler.HandlerResult
---@field handled boolean

---@class neotree.Config.EventHandler
---@field event string
---@field handler fun(table?):neotree.Config.EventHandler.HandlerResult?

---@alias neotree.Config.BorderStyle "NC"|"none"|"rounded"|"shadow"|"single"|"solid"|nil

---@class neotree.Config
---@field sources string[]?
---@field add_blank_line_at_top boolean?
---@field auto_clean_after_session_restore boolean?
---@field close_if_last_window boolean?
---@field default_source string?
---@field enable_diagnostics boolean?
---@field enable_git_status boolean?
---@field enable_modified_markers boolean?
---@field enable_opened_markers boolean?
---@field enable_refresh_on_write boolean?
---@field enable_cursor_hijack boolean?
---@field git_status_async boolean?
---@field git_status_async_options neotree.Config.GitStatusAsync?
---@field hide_root_node boolean?
---@field retain_hidden_root_indent boolean?
---@field log_level "trace"|"debug"|"info"|"warn"|"error"|"fatal"|nil
---@field log_to_file boolean?
---@field open_files_in_last_window boolean?
---@field open_files_do_not_replace_types string[]?
---@field open_files_using_relative_paths boolean?
---@field popup_border_style neotree.Config.BorderStyle
---@field resize_timer_interval integer?
---@field sort_case_insensitive boolean?
---@field sort_function fun(a: any, b: any)?
---@field use_popups_for_input boolean?
---@field use_default_mappings boolean?
---@field source_selector neotree.Config.SourceSelector?
---@field event_handlers table[]?
---@field default_component_configs neotree.Config.Components?
---@field renderers neotree.Config.Renderers[]?
---@field nesting_rules table[]? -- TODO, merge rework
---@field commands table<string, fun()>?
---@field window neotree.Config.Window?
---@field filesystem neotree.Config.Filesystem?
---@field buffers neotree.Config.Buffers?
---@field git_status neotree.Config.GitStatus?
