---@class NeotreeConfig.components
---@field container NeotreeComponent.container|nil
---@field diagnostics NeotreeComponent.diagnostics|nil
---@field indent NeotreeComponent.indent|nil
---@field icon NeotreeComponent.icon|nil
---@field modified NeotreeComponent.modified|nil
---@field name NeotreeComponent.name|nil
---@field git_status NeotreeComponent.git_status|nil
---@field [NeotreeConfig.components.enum] NeotreeComponentBase|nil

---@alias NeotreeConfig.components.enum
---|"container"
---|"diagnostics"
---|"indent"
---|"icon"
---|"modified"
---|"name"
---|"git_status"
---|"file_size"
---|"file_time"
---|"type"
---|"last_modified"
---|"created"
---|"symlink_target"
---|"bufnr"
---|"clipboard"
---|"current_filter"
---|"filtered_by"
---|"bufnr"
---|"kind_icon"
---|"kind_name"

---@class NeotreeComponentBase : { [1]: NeotreeConfig.components.enum }
---@field enabled boolean|nil (true) You can set `enabled = false` for each of them individually
---@field required_width integer|nil (64) min width of window required to show this column
---@field zindex integer|nil
---@field align "left"|"right"|nil ("left") # Where to place the component. Defaults to "left".
---@field content NeotreeComponentBase[]|nil
---@field highlight NeotreeConfig.highlight|nil (nil)
---@field hide_when_expanded boolean|nil (nil)

---@class NeotreeComponent.container : NeotreeComponentBase
---@field enable_character_fade boolean|nil (true)
---@field width NeotreeConfig.wh|nil ("100%")
---@field right_padding integer|nil (0)

---@class NeotreeComponent.diagnostics : NeotreeComponentBase
---@field errors_only boolean|nil
---@field symbols { [NeotreeConfig.diagnostics_keys]: string }|nil
---@field highlights { [NeotreeConfig.diagnostics_keys]: NeotreeConfig.highlight }|nil

---@class NeotreeComponent.indent : NeotreeComponentBase
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

---@class NeotreeComponent.icon : NeotreeComponentBase
---@field folder_closed string|nil ("")
---@field folder_open string|nil ("")
---@field folder_empty string|nil ("󰉖")
---@field folder_empty_open string|nil ("󰷏")
---@field default string|nil ("*") # Used as a fallback.
---@field highlight NeotreeConfig.highlight|nil ("NeoTreeFileIcon") # Used as a fallback.

---@class NeotreeComponent.modified : NeotreeComponentBase
---@field symbol string|nil ("[+] ")
---@field highlight NeotreeConfig.highlight|nil ("NeoTreeModified")

---@class NeotreeComponent.name : NeotreeComponentBase
---@field trailing_slash boolean|nil (false)
---@field right_padding integer|nil (0)
---@field highlight_opened_files NeotreeComponent.name.highlight_opened_files|nil (false) Requires `enable_opened_markers = true`.
---@field use_git_status_colors boolean|nil (true)
---@field highlight NeotreeConfig.highlight|nil ("NeoTreeFileName")

---@alias NeotreeComponent.name.highlight_opened_files
---|true  # Hightlight only loaded files
---|false # Do nothing
---|"all" # Highlight both loaded and unloaded files

---@class NeotreeComponent.git_status : NeotreeComponentBase
---@field symbols { [NeotreeComponent.git_status.symbol_change|NeotreeComponent.git_status.symbol_status]: string }|nil
---@field align NeotreeConfig.components.align|nil ("right")

---@alias NeotreeComponent.git_status.symbol_change "added" | "deleted" | "modified" | "renamed"
---@alias NeotreeComponent.git_status.symbol_status "untracked" | "ignored" | "unstaged" | "staged" | "conflict"
