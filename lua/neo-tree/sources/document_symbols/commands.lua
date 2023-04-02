--This file should contain all commands meant to be used by mappings.
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")

local vim = vim

local M = {}

M.refresh = utils.wrap(manager.refresh, "git_status")
M.redraw = utils.wrap(manager.redraw, "git_status")

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

M.jump_to_symbol = function(state)
  local node = state.tree:get_node()
  vim.api.nvim_set_current_win(state.lsp_winid)
  local symbol_loc = node.extra.selection_range.start
  vim.api.nvim_win_set_cursor(state.lsp_winid, { symbol_loc.row, symbol_loc.col })
end

cc._add_common_commands(M)
return M
