---@meta

---@alias neotree.Renderer fun(config: table, node: table, state: table):(neotree.Render.Node|neotree.Render.Node[])

---@class (exact) neotree.Render.Node
---@field text string The text to display.
---@field highlight string The highlight for the text.

---@class (exact) neotree.Component
---@field [1] string?
---@field enabled boolean?
---@field highlight string?

---@alias neotree.IconProvider fun(icon: table, node: table, state: table):(neotree.Render.Node|neotree.Render.Node[]|nil)
