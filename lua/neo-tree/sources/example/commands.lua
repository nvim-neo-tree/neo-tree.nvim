--This file should contain all commands meant to be used by mappings.

local vim = vim

local M = {}

M.example_command = function(state)
  local tree = state.tree
  local node = tree:get_node()
  local id = node:get_id()
  local name = node:get_name()
  print(string.format("example_command: id=%s, name=%s", id, name))
end

M.show_debug_info = function(state)
  print(vim.inspect(state))
end

return M
