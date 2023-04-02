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

M.icon = function(config, node, state)
  local padding = config.padding or " "
  local has_children_icon = " "
  if node:has_children() then
    has_children_icon = node:is_expanded() and "" or ""
  end

  local highlight = node.extra.kind.hl or config.highlight or highlights.FILE_ICON

  return {
    text = has_children_icon .. padding,
    highlight = highlight,
  }
end

M.kind = function(config, node, state)
  local padding = config.padding or " "
  local kind = node.extra.kind

  local text = config.align == "right" and kind.name .. padding .. kind.icon .. padding
    or padding .. kind.icon .. padding .. kind.name
  if node:get_depth() == 1 then
    text = ""
  end

  return {
    text = text,
    highlight = kind.hl,
  }
end

M.name = function(config, node, state)
  local padding = config.padding or " "
  local highlight = node.extra.kind.hl or config.highlight or highlights.FILE_NAME
  local text = node.name
  if node:get_depth() == 1 then
    text = "SYMBOLS in " .. node.name
  end
  return {
    text = text,
    highlight = highlight,
  }
end

return vim.tbl_deep_extend("force", common, M)
