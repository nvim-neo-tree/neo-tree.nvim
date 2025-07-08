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
local utils = require("neo-tree.utils")

---@alias neotree.Component.Buffers._Key
---|"name"

---@class neotree.Component.Buffers
---@field [1] neotree.Component.Buffers._Key|neotree.Component.Common._Key

---@type table<neotree.Component.Buffers._Key, neotree.Renderer>
local M = {}

---@class (exact) neotree.Component.Buffers.Name : neotree.Component.Common.Name

---@param config neotree.Component.Buffers.Name
M.name = function(config, node, state)
  local highlight = config.highlight or highlights.FILE_NAME_OPENED
  local name = node.name
  if node.type == "directory" then
    if node:get_depth() == 1 then
      highlight = highlights.ROOT_NAME
      name = "OPEN BUFFERS in " .. name
    else
      highlight = highlights.DIRECTORY_NAME
    end
  elseif node.type == "terminal" then
    if node:get_depth() == 1 then
      highlight = highlights.ROOT_NAME
      name = "TERMINALS"
    else
      highlight = highlights.FILE_NAME
    end
  elseif config.use_git_status_colors then
    local git_status = state.components.git_status({}, node, state)
    if git_status and git_status.highlight then
      highlight = git_status.highlight
    end
  end
  return {
    text = name,
    highlight = highlight,
  }
end

return vim.tbl_deep_extend("force", common, M)
