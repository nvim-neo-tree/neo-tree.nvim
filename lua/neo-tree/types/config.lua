---@meta

---@class neotree.Config.MappingOptions
---@field noremap boolean?
---@field nowait boolean?

---@class neotree.Config.Mapping : neotree.Config.MappingOptions
---@field [1] string
---@field nowait boolean?
---@field noremap boolean?
---@field config table?

---@class neotree.Config.Source
---@field window neotree.Config.Source.Window?
---@field renderers neotree.Component[]?

---@class neotree.Config.Source.Window
---@field mappings table<string, string|neotree.Config.Mapping>?

---@class neotree.Config.SourceSelector.Item
---@field source string?
---@field padding integer|{left:integer,right:integer}?
---@field separator string|{left:string,right:string, override?:string}?

---@alias neotree.Config.SourceSelector.Separator.Override
---|"right"   # When right and left separators meet, only show the right one.
---|"left"    # When right and left separators meet, only show the left one.
---|"active"  # Only use the left separator on the left of the active tab, and only the right afterwards.
---|nil       # Show both separators.

---@class neotree.Config.SourceSelector.Separator
---@field left string?
---@field right string?
---@field override neotree.Config.SourceSelector.Separator.Override?

---@class neotree.Config.SourceSelector
---@field winbar boolean?
---@field statusline boolean?
---@field show_scrolled_off_parent_node boolean?
---@field sources neotree.Config.SourceSelector.Item[]?
---@field content_layout string? "start"|"end"|"center"
---@field tabs_layout string? "equal"|"start"|"end"|"center"|"focus"
---@field truncation_character string
---@field tabs_min_width integer?
---@field tabs_max_width integer?
---@field padding integer|{left: integer, right:integer}?
---@field separator neotree.Config.SourceSelector.Separator?
---@field separator_active neotree.Config.SourceSelector.Separator?
---@field show_separator_on_edge boolean?
---@field highlight_tab string?
---@field highlight_tab_active string?
---@field highlight_background string?
---@field highlight_separator string?
---@field highlight_separator_active string?

---@class neotree.Config.GitStatusAsync
---@field batch_size integer?
---@field batch_delay integer?
---@field max_lines integer?

---@class neotree.Config.Window.Size
---@field height string|number?
---@field width string|number?

---@class neotree.Config.Window.Popup
---@field title fun(state:table):string?
---@field size neotree.Config.Window.Size?
---@field border neotree.Config.BorderStyle?

---@class neotree.Config.Window
---@field position string?
---@field width integer?
---@field height integer?
---@field auto_expand_width boolean?
---@field popup neotree.Config.Window.Popup?
---@field same_level boolean?
---@field insert_as "child"|"sibling"|nil
---@field mapping_options neotree.Config.MappingOptions?
---@field mappings neotree.Config.Mapping[]?

---@class neotree.Config.Renderers
---@field directory neotree.Component.Common[]?
---@field file neotree.Component.Common[]?
---@field message neotree.Component.Common[]?
---@field terminal neotree.Component.Common[]?

---@class neotree.Config.ComponentDefaults
---@field container neotree.Component.Common.Container?
---@field indent neotree.Component.Common.Indent?
---@field icon neotree.Component.Common.Icon?
---@field modified neotree.Component.Common.Modified?
---@field name neotree.Component.Common.Name?
---@field git_status neotree.Component.Common.GitStatus?
---@field file_size neotree.Component.Common.FileSize?
---@field type neotree.Component.Common.Type?
---@field last_modified neotree.Component.Common.LastModified?
---@field created neotree.Component.Common.Created?
---@field symlink_target neotree.Component.Common.SymlinkTarget?

---@alias neotree.Config.BorderStyle "NC"|"none"|"rounded"|"shadow"|"single"|"solid"

---@class (exact) neotree.Config.Base
---@field sources string[]
---@field add_blank_line_at_top boolean
---@field auto_clean_after_session_restore boolean
---@field close_if_last_window boolean
---@field default_source string
---@field enable_diagnostics boolean
---@field enable_git_status boolean
---@field enable_modified_markers boolean
---@field enable_opened_markers boolean
---@field enable_refresh_on_write boolean
---@field enable_cursor_hijack boolean
---@field git_status_async boolean
---@field git_status_async_options neotree.Config.GitStatusAsync
---@field hide_root_node boolean
---@field retain_hidden_root_indent boolean
---@field log_level "trace"|"debug"|"info"|"warn"|"error"|"fatal"|nil
---@field log_to_file boolean|string
---@field open_files_in_last_window boolean
---@field open_files_do_not_replace_types string[]
---@field open_files_using_relative_paths boolean
---@field popup_border_style neotree.Config.BorderStyle
---@field resize_timer_interval integer|-1
---@field sort_case_insensitive boolean
---@field sort_function? fun(a: any, b: any):boolean
---@field use_popups_for_input boolean
---@field use_default_mappings boolean
---@field source_selector neotree.Config.SourceSelector
---@field event_handlers? neotree.Event.Handler[]
---@field default_component_configs neotree.Config.ComponentDefaults
---@field renderers neotree.Config.Renderers
---@field nesting_rules neotree.FileNesting.Rule[]
---@field commands table<string, fun()>
---@field window neotree.Config.Window
---
---@field filesystem neotree.Config.Filesystem
---@field buffers neotree.Config.Buffers
---@field git_status neotree.Config.GitStatus
---@field document_symbols neotree.Config.DocumentSymbols

---@class (exact) neotree.Config._Full : neotree.Config.Base
---@field prior_windows table<string, integer[]>?

---@class (partial) neotree.Config : neotree.Config.Base
