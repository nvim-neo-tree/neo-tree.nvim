--This file should contain all commands meant to be used by mappings.

local vim = vim
local fs = require('neo-tree.sources.filesystem')
local fs_actions = require('neo-tree.sources.filesystem.lib.fs_actions')
local utils = require('neo-tree.utils')
local filter = require("neo-tree.sources.filesystem.lib.filter")

local M = {}

M.add = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'file' then
    node = tree:get_node(node:get_parent_id())
  end
  fs_actions.create_node(node:get_id(), function()
    fs.show_new_children(node)
  end)
end

M.clear_filter = function(state)
  fs.reset_search(true)
end

---Marks node as copied, so that it can be pasted somewhere else.
M.copy_to_clipboard = function(state)
  local node = state.tree:get_node()
  state.clipboard = state.clipboard or {}
  local existing = state.clipboard[node.id]
  if existing and existing.action == "copy" then
    state.clipboard[node.id] = nil
  else
    state.clipboard[node.id] = { action = "copy", node = node }
    print("Copied " .. node.name .. " to clipboard")
  end
  fs.redraw()
end

---Marks node as cut, so that it can be pasted (moved) somewhere else.
M.cut_to_clipboard = function(state)
  local node = state.tree:get_node()
  state.clipboard = state.clipboard or {}
  local existing = state.clipboard[node.id]
  if existing and existing.action == "cut" then
    state.clipboard[node.id] = nil
  else
    state.clipboard[node.id] = { action = "cut", node = node }
    print("Cut " .. node.name .. " to clipboard")
  end
  fs.redraw()
end

M.show_debug_info = function(state)
  print(vim.inspect(state))
end

---Pastes all items from the clipboard to the current directory.
M.paste_from_clipboard = function(state)
  if state.clipboard then
    local at_node = state.tree:get_node()
    local folder = at_node:get_id()
    if at_node.type == "file" then
      folder = at_node:get_parent_id()
    end
    for _, item in pairs(state.clipboard) do
      if item.action == "copy" then
        fs_actions.copy_node(item.node.path, folder .. utils.path_separator .. item.node.name)
      elseif item.action == "cut" then
        fs_actions.move_node(item.node.path, folder .. utils.path_separator .. item.node.name)
      end
    end
    state.clipboard = nil
    fs.refresh()

    -- open the folder so the user can see the new files
    local node = state.tree:get_node(folder)
    if not node then
      print("Could not find node for " .. folder)
      return
    end
    fs.show_new_children(node)
  end
end

M.delete = function(state)
  local tree = state.tree
  local node = tree:get_node()

  fs_actions.delete_node(node.path, fs.refresh)
end

---Shows the filter input, which will filter the tree.
M.filter_as_you_type = function(state)
  filter.show_filter(state, true)
end

---Shows the filter input, which will filter the tree.
M.filter_on_submit = function(state)
  filter.show_filter(state, false)
end

---Navigate up one level.
M.navigate_up = function(state)
  local parent_path, _ = utils.split_path(state.path)
  if state.search_pattern then
    fs.reset_search(false)
  end
  fs.navigate(parent_path)
end

local open_with_cmd = function(state, open_cmd)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'directory' then
    fs.toggle_directory()
    return nil
  else
    if state.window.position == "right" then
      vim.cmd("wincmd t")
    else
      vim.cmd("wincmd w")
    end
    vim.cmd(open_cmd .. " " .. node:get_id())
  end
end

M.open = function(state)
  open_with_cmd(state, "e")
end

M.open_split = function(state)
  open_with_cmd(state, "split")
end

M.open_vsplit = function(state)
  open_with_cmd(state, "vsplit")
end

M.refresh = fs.refresh

M.rename = function(state)
  local tree = state.tree
  local node = tree:get_node()
  fs_actions.rename_node(node.path, fs.refresh)
end

M.set_root = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'directory' then
    if state.search_pattern then
      fs.reset_search(false)
    end
    fs.navigate(node.id)
  end
end

---Toggles whether hidden files are shown or not.
M.toggle_hidden = function(state)
  state.show_hidden = not state.show_hidden
  fs.show()
end

---Toggles whether the tree is filtered by gitignore or not.
M.toggle_gitignore = function(state)
  state.respect_gitignore = not state.respect_gitignore
  fs.show()
end

return M
