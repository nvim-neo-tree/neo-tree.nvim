--This file should contain all commands meant to be used by mappings.

local vim = vim
local cc = require("neo-tree.sources.common.commands")
local buffers = require("neo-tree.sources.buffers")
local utils = require("neo-tree.utils")

local M = {}

M.add = function(state)
  cc.add(state, buffers.refresh)
end

M.close_node = cc.close_node

---Marks node as copied, so that it can be pasted somewhere else.
M.copy_to_clipboard = function(state)
  cc.copy_to_clipboard(state, buffers.redraw)
end

---Marks node as cut, so that it can be pasted (moved) somewhere else.
M.cut_to_clipboard = function(state)
  cc.cut_to_clipboard(state, buffers.redraw)
end

M.show_debug_info = cc.show_debug_info

---Pastes all items from the clipboard to the current directory.
M.paste_from_clipboard = function(state)
  cc.paste_from_clipboard(state, buffers.refresh)
end

M.delete = function(state)
  cc.delete(state, buffers.refresh)
end

---Navigate up one level.
M.navigate_up = function(state)
  local parent_path, _ = utils.split_path(state.path)
  buffers.navigate(parent_path)
end

M.open = cc.open
M.open_split = cc.open_split
M.open_vsplit = cc.open_vsplit

M.refresh = buffers.refresh

M.rename = function(state)
  cc.rename(state, buffers.refresh)
end

M.set_root = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == "directory" then
    buffers.navigate(node.id)
  end
end

return M
