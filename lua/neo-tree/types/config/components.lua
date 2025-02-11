---@class neotree.Config.Component.Container
---@field enable_character_fade boolean
---@field width string
---@field right_padding integer

---@class neotree.Config.Component.Indent
---@field indent_size integer
---@field padding integer
---@field with_markers boolean
---@field indent_marker string
---@field last_indent_marker string
---@field highlight string
---@field with_expanders boolean?
---@field expander_collapsed string
---@field expander_expanded string
---@field expander_highlight string

---@class neotree.Config.Component.Icon
---@field folder_closed string
---@field folder_open string
---@field folder_empty string
---@field folder_empty_open string
---@field default string
---@field highlight string
---@field provider fun(icon:table, node:table, state:table)

---@class neotree.Config.Component.Modified
---@field symbol string
---@field highlight string

---@class neotree.Config.Component.Name
---@field trailing_slash boolean
---@field highlight_opened_files boolean|"all"
---@field use_git_status_colors boolean
---@field highlight string

---@class neotree.Config.Component.GitStatus.Symbols
---@field added string
---@field deleted string
---@field modified string
---@field renamed string
---@field untracked string
---@field ignored string
---@field unstaged string
---@field staged string
---@field conflict string

---@class neotree.Config.Component.GitStatus
---@field symbols neotree.Config.Component.GitStatus.Symbols
---@field align string

---@class neotree.Config.Component.FileSize
---@field enabled boolean
---@field width integer
---@field required_width integer

---@class neotree.Config.Component.Type
---@field enabled boolean
---@field width integer
---@field required_width integer

---@class neotree.Config.Component.LastModified
---@field enabled boolean
---@field width integer
---@field required_width integer
---@field format string|fun(seconds:number):string

---@class neotree.Config.Component.Created
---@field enabled boolean
---@field width integer
---@field required_width integer
---@field format string|fun(seconds:number):string

---@class neotree.Config.Component.SymlinkTarget
---@field enabled boolean
---@field text_format string

---@class neotree.Config.Components
---@field container neotree.Config.Component.Container
---@field indent neotree.Config.Component.Indent
---@field icon neotree.Config.Component.Icon
---@field modified neotree.Config.Component.Modified
---@field name neotree.Config.Component.Name
---@field git_status neotree.Config.Component.GitStatus
---@field file_size neotree.Config.Component.FileSize
---@field type neotree.Config.Component.Type
---@field last_modified neotree.Config.Component.LastModified
---@field created neotree.Config.Component.Created
---@field symlink_target neotree.Config.Component.SymlinkTarget

---@class neotree.Renderer.Container
---@field content table
---@field zindex integer?
---@field align string?
---@field hide_when_expanded boolean?

---@alias neotree.Renderer.Components table

---@class neotree.Config.Renderers
---@field directory neotree.Renderer.Components[]
---@field file neotree.Renderer.Components[]
---@field message neotree.Renderer.Components[]
---@field terminal neotree.Renderer.Components[]
