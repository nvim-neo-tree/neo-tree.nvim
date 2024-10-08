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

local M = {}

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

M.kind_name = function(config, node, state)
  return {
    text = node:get_depth() == 1 and "" or node.extra.kind.name,
    highlight = node.extra and node.extra.kind.hl or highlights.FILE_NAME,
  }
end

M.name = function(config, node, state)
  return {
    text = node.name,
    highlight = node.extra and node.extra.kind.hl or highlights.FILE_NAME,
  }
end

return vim.tbl_deep_extend("force", common, M)
