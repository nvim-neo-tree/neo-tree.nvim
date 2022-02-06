--This file should contain all commands meant to be used by mappings.

local vim = vim
local cc = require("neo-tree.sources.common.commands")
local buffers = require("neo-tree.sources.buffers")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")

local M = {}

local refresh = utils.wrap(manager.refresh, "git_status")
local redraw = utils.wrap(manager.redraw, "git_status")

M.add = function(state)
  cc.add(state, refresh)
end

M.buffer_delete = function(state)
  local node = state.tree:get_node()
  if node then
    vim.api.nvim_buf_delete(node.extra.bufnr, { force = false, unload = false })
    refresh()
  end
end

M.close_node = cc.close_node
M.close_window = cc.close_window

---Marks node as copied, so that it can be pasted somewhere else.
M.copy_to_clipboard = function(state)
  cc.copy_to_clipboard(state, redraw)
end

---Marks node as cut, so that it can be pasted (moved) somewhere else.
M.cut_to_clipboard = function(state)
  cc.cut_to_clipboard(state, redraw)
end

M.show_debug_info = cc.show_debug_info

---Pastes all items from the clipboard to the current directory.
M.paste_from_clipboard = function(state)
  cc.paste_from_clipboard(state, refresh)
end

M.delete = function(state)
  cc.delete(state, refresh)
end

---Navigate up one level.
M.navigate_up = function(state)
  local parent_path, _ = utils.split_path(state.path)
  buffers.navigate(parent_path)
end

M.open = cc.open
M.open_split = cc.open_split
M.open_vsplit = cc.open_vsplit

M.refresh = refresh

M.rename = function(state)
  cc.rename(state, refresh)
end

M.set_root = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == "directory" then
    buffers.navigate(node.id)
  end
end

return M
