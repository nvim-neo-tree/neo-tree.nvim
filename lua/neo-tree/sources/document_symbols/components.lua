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

M.kind_icon = function(config, node, state)
  local padding = config.padding or " "
  local icon = node.extra.kind.icon

  icon = config.align == "right" and icon .. padding or padding .. icon
  if node:get_depth() == 1 then
    icon = ""
  end

  return {
    text = icon,
    highlight = node.extra.kind.hl,
  }
end

M.kind_name = function(config, node, state)
  local padding = config.padding or " "
  local name = node.extra.kind.name

  name = config.align == "right" and name .. padding or padding .. name
  if node:get_depth() == 1 then
    name = ""
  end

  return {
    text = name,
    highlight = node.extra.kind.hl,
  }
end

M.name = function(config, node, state)
  local padding = config.padding or " "
  local highlight = node.extra.kind.hl or highlights.FILE_NAME
  local text = node.name
  if node:get_depth() == 1 then
    text = "SYMBOLS " .. node.name
  end
  return {
    text = text,
    highlight = highlight,
  }
end

return vim.tbl_deep_extend("force", common, M)
