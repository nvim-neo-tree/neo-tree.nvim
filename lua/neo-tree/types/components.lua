---@meta

---@alias neotree.Renderer fun(config: table, node: NuiTree.Node, state: neotree.StateWithTree):(neotree.Render.Node|neotree.Render.Node[])

---@alias neotree.FileRenderer fun(config: table, node: neotree.FileNode, state: neotree.StateWithTree):(neotree.Render.Node|neotree.Render.Node[])

---@class (exact) neotree.Render.Node
---@field text string The text to display.
---@field highlight string The highlight for the text.

---@class (exact) neotree.Component
---@field [1] string?
---@field enabled boolean?
---@field highlight string?

---@alias neotree.IconProvider fun(icon: neotree.Render.Node, node: NuiTree.Node, state: neotree.StateWithTree):(neotree.Render.Node|neotree.Render.Node[]|nil)
