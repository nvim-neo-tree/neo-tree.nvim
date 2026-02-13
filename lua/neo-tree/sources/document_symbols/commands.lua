--This file should contain all commands meant to be used by mappings.
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")
local inputs = require("neo-tree.ui.inputs")
local filters = require("neo-tree.sources.common.filters")

---@class neotree.sources.DocumentSymbols.Commands : neotree.sources.Common.Commands
---@field [string] neotree.TreeCommand
local M = {}
local SOURCE_NAME = "document_symbols"
M.refresh = utils.wrap(manager.refresh, SOURCE_NAME)
M.redraw = utils.wrap(manager.redraw, SOURCE_NAME)

M.show_debug_info = function(state)
  print(vim.inspect(state))
end

---@param node NuiTree.Node
M.jump_to_symbol = function(state, node)
  node = node or state.tree:get_node()
  if node:get_depth() == 1 then
    return
  end
  vim.api.nvim_set_current_win(state.lsp_winid)
  vim.api.nvim_set_current_buf(state.lsp_bufnr)
  local symbol_loc = node.extra.selection_range.start
  vim.api.nvim_win_set_cursor(state.lsp_winid, { symbol_loc[1] + 1, symbol_loc[2] })
end

---Show symbol location without changing focus
---@param state table
---@param node NuiTree.Node|nil
M.show_symbol = function(state, node)
  if not state or not state.tree then
    return
  end
  node = node or state.tree:get_node()
  if not node or node:get_depth() == 1 then
    return
  end

  local neo_win = vim.api.nvim_get_current_win()
  local symbol_loc = node.extra.selection_range.start

  -- Jump to symbol in target window
  vim.api.nvim_win_call(state.lsp_winid, function()
    if vim.api.nvim_win_get_buf(state.lsp_winid) ~= state.lsp_bufnr then
      vim.api.nvim_win_set_buf(state.lsp_winid, state.lsp_bufnr)
    end
    pcall(vim.api.nvim_win_set_cursor, state.lsp_winid, { symbol_loc[1] + 1, symbol_loc[2] })
  end)

  -- Restore focus to neo-tree
  if vim.api.nvim_win_is_valid(neo_win) then
    vim.api.nvim_set_current_win(neo_win)
  end
end

M.rename = function(state)
  local node = assert(state.tree:get_node())
  if node:get_depth() == 1 then
    return
  end
  local old_name = node.name

  ---@param new_name string?
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

M.filter_on_submit = function(state)
  filters.show_filter(state, true, true)
end

M.filter = function(state)
  filters.show_filter(state, true)
end

cc._add_common_commands(M, "node") -- common tree commands
cc._add_common_commands(M, "^open") -- open commands
cc._add_common_commands(M, "^close_window$")
cc._add_common_commands(M, "source$") -- source navigation
cc._add_common_commands(M, "preview") -- preview
cc._add_common_commands(M, "^cancel$") -- cancel
cc._add_common_commands(M, "help") -- help commands
cc._add_common_commands(M, "with_window_picker$") -- open using window picker
cc._add_common_commands(M, "^toggle_auto_expand_width$")

return M
