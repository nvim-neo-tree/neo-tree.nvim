-- This file contains the built-in components. Each componment is a function
-- that takes the following arguments:
--      config: A table containing the configuration provided by the user
--              when declaring this component in their renderer config.
--      node:   A NuiNode object for the currently focused node.
--      state:  The current state of the source providing the items.
--
-- The function should return either a table, or a list of tables, each of which
-- contains the following keys:
--    text:      The text to display for this item.
--    highlight: The highlight group to apply to this text.

local highlights = require("neo-tree.ui.highlights")
local common = require("neo-tree.sources.common.components")

---@alias neotree.Component.DocumentSymbols._Key
---|"kind_icon"
---|"kind_name"
---|"name"

---@class neotree.Component.DocumentSymbols Use the neotree.Component.DocumentSymbols.* types to get more specific types.
---@field [1] neotree.Component.DocumentSymbols._Key|neotree.Component.Common._Key

---@type table<neotree.Component.DocumentSymbols._Key, neotree.Renderer>
local M = {}

---@class (exact) neotree.Component.DocumentSymbols.KindIcon : neotree.Component
---@field [1] "kind_icon"?
---@field provider neotree.IconProvider?

---@param config neotree.Component.DocumentSymbols.KindIcon
M.kind_icon = function(config, node, state)
  local icon = {
    text = node:get_depth() == 1 and "" or node.extra.kind.icon,
    highlight = node.extra.kind.hl,
  }

  if config.provider then
    icon = config.provider(icon, node, state) or icon
  end

  return icon
end

---@class (exact) neotree.Component.DocumentSymbols.KindName : neotree.Component
---@field [1] "kind_name"?

---@param config neotree.Component.DocumentSymbols.KindName
M.kind_name = function(config, node, state)
  return {
    text = node:get_depth() == 1 and "" or node.extra.kind.name,
    highlight = node.extra and node.extra.kind.hl or highlights.FILE_NAME,
  }
end

---@class (exact) neotree.Component.DocumentSymbols.Name : neotree.Component.Common.Name

---@param config neotree.Component.DocumentSymbols.Name
M.name = function(config, node, state)
  return {
    text = node.name,
    highlight = node.extra and node.extra.kind.hl or highlights.FILE_NAME,
  }
end

return vim.tbl_deep_extend("force", common, M)
