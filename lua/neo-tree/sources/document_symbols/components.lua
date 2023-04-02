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
local kind = require("neo-tree.sources.document_symbols.lib.kind")

local M = {}

M.custom = function(config, node, state)
  local text = node.extra.custom_text or ""
  local highlight = highlights.DIM_TEXT
  return {
    text = text .. " ",
    highlight = highlight,
  }
end

M.icon = function(config, node, state)
  local icon = config.default or " "
  local padding = config.padding or " "
  local highlight = config.highlight or highlights.FILE_ICON

  icon = string.sub(node.extra.kind, 1, 1)

  return {
    text = icon .. padding,
    highlight = highlight,
  }
end

M.name = function(config, node, state)
  local highlight = config.highlight or highlights.FILE_NAME
  local text = node.name
  if node:get_depth() == 1 then
    text = "SYMBOLS in " .. node.name
    highlight = highlights.ROOT_NAME
  end
  return {
    text = text,
    highlight = highlight,
  }
end

return vim.tbl_deep_extend("force", common, M)
