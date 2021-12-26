--This file should contain all commands meant to be used by mappings.

local vim = vim
local fs = require('neo-tree.sources.filesystem')
local fs_actions = require('neo-tree.sources.filesystem.fs_actions')
local utils      = require('neo-tree.utils')

local commands = {}

commands.add = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'file' then
    node = tree:get_node(node:get_parent_id())
  end
  fs_actions.create_node(node:get_id(), function()
    fs.show_new_children(node)
  end)
end

commands.copy_to_clipboard = fs.copy_to_clipboard
commands.cut_to_clipboard = fs.cut_to_clipboard
commands.paste_from_clipboard = fs.paste_from_clipboard

commands.delete = function(state)
  local tree = state.tree
  local node = tree:get_node()

  fs_actions.delete_node(node.path, fs.refresh)
end

commands.open = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'directory' then
    fs.toggle_directory()
  else
    if state.window.position == "right" then
      vim.cmd("wincmd t")
    else
      vim.cmd("wincmd w")
    end
    vim.cmd("e " .. node.id)
  end
end

commands.paste_from_clipboard = fs.paste_from_clipboard

commands.refresh = fs.refresh

commands.rename = function(state)
  local tree = state.tree
  local node = tree:get_node()
  fs_actions.rename_node(node.path, fs.refresh)
end

commands.search = fs.search

commands.set_root = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'directory' then
    fs.navigate(node.id)
  end
end

commands.toggle_hidden = fs.toggle_hidden

commands.toggle_gitignore = fs.toggle_gitignore

commands.up = fs.navigate_up

return commands
