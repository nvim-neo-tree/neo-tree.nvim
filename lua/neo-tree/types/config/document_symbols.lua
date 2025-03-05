---@meta

---@class neotree.Config.LspKindDisplay
---@field icon string
---@field hl string

---@class neotree.Config.DocumentSymbols.Renderers : neotree.Config.Renderers
---@field root neotree.Component.DocumentSymbols[]?
---@field symbol neotree.Component.DocumentSymbols[]?

---@class (exact) neotree.Config.DocumentSymbols : neotree.Config.Source
---@field follow_cursor boolean?
---@field client_filters neotree.lsp.ClientFilter?
---@field custom_kinds table<integer, string>?
---@field kinds table<string, neotree.Config.LspKindDisplay>?
---@field renderers neotree.Config.DocumentSymbols.Renderers?
