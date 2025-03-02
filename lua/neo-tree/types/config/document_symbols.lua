---@meta

---@class neotree.Config.LspKindDisplay
---@field icon string
---@field hl string

---@class neotree.Config.DocumentSymbols : neotree.Config.Source
---@field follow_cursor boolean
---@field client_filters neotree.lsp.ClientFilter
---@field custom_kinds table<integer, string>
---@field kinds table<string, neotree.Config.LspKindDisplay>
---@field renderers (neotree.Component.DocumentSymbols|neotree.Component.Common)[]
