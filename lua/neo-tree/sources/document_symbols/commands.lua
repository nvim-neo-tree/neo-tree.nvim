--This file should contain all commands meant to be used by mappings.
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")
local inputs = require("neo-tree.ui.inputs")
local popups = require("neo-tree.ui.popups")
local log = require("neo-tree.log")

local vim = vim

local M = {}
local SOURCE_NAME = "document_symbols"
M.refresh = utils.wrap(manager.refresh, SOURCE_NAME)
M.redraw = utils.wrap(manager.redraw, SOURCE_NAME)

M.example_command = function(state)
  local tree = state.tree
  local node = tree:get_node()
  local id = node:get_id()
  local name = node.name
  print(vim.inspect(node.extra))
end

M.show_debug_info = function(state)
  print(vim.inspect(state))
end

M.jump_to_symbol = function(state, node)
  node = node or state.tree:get_node()
  if node:get_depth() == 1 then
    return
  end
  vim.api.nvim_set_current_win(state.lsp_winid)
  local symbol_loc = node.extra.selection_range.start
  vim.api.nvim_win_set_cursor(state.lsp_winid, { symbol_loc[1], symbol_loc[2] })
end

M.rename = function(state)
  local node = state.tree:get_node()
  if node:get_depth() == 1 then
    return
  end
  local old_name = node.name

  local callback = function(new_name)
    if not new_name or new_name == "" or new_name == old_name then
      return
    end
    M.jump_to_symbol(state, node)
    vim.lsp.buf.rename(new_name)
    M.refresh(state)
  end
  local msg = string.format('Enter new name for "%s":', old_name)
  inputs.input(msg, old_name, callback)
end

M.open = M.jump_to_symbol

-- mask away default commands
M.add = function() end
M.add_directory = M.add
M.copy = M.add
M.delete = M.add
M.delete_visual = M.add
M.move = M.add
M.paste_from_clipboard = M.add
M.cut_to_clipboard = M.add
M.copy_to_clipboard = M.add

cc._add_common_commands(M)
return M
