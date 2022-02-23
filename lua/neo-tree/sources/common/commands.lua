--This file should contain all commands meant to be used by mappings.

local vim = vim
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local log = require("neo-tree.log")

local M = {}

---Add a new file or dir at the current node
---@param state table The state of the source
---@param callback function The callback to call when the command is done. Called with the parent node as the argument.
M.add = function(state, callback)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == "file" then
    node = tree:get_node(node:get_parent_id())
  end
  fs_actions.create_node(node:get_id(), callback)
end

M.close_all_nodes = function(state)
  renderer.collapse_all_nodes(state.tree)
  state.tree:get_nodes()[1]:expand()
  state.tree:render()
end

M.close_node = function(state, callback)
  local tree = state.tree
  local node = tree:get_node()
  local parent_node = tree:get_node(node:get_parent_id())
  local target_node

  if node.type == "directory" and node:is_expanded() then
    target_node = node
  else
    target_node = parent_node
  end

  if target_node then
    target_node:collapse()
    tree:render()
    renderer.focus_node(state, target_node:get_id())
  end
end

M.close_window = function(state)
  renderer.close(state)
end

---Marks node as copied, so that it can be pasted somewhere else.
M.copy_to_clipboard = function(state, callback)
  local node = state.tree:get_node()
  state.clipboard = state.clipboard or {}
  local existing = state.clipboard[node.id]
  if existing and existing.action == "copy" then
    state.clipboard[node.id] = nil
  else
    state.clipboard[node.id] = { action = "copy", node = node }
    log.info("Copied " .. node.name .. " to clipboard")
  end
  if callback then
    callback()
  end
end

---Marks node as cut, so that it can be pasted (moved) somewhere else.
M.cut_to_clipboard = function(state, callback)
  local node = state.tree:get_node()
  state.clipboard = state.clipboard or {}
  local existing = state.clipboard[node.id]
  if existing and existing.action == "cut" then
    state.clipboard[node.id] = nil
  else
    state.clipboard[node.id] = { action = "cut", node = node }
    log.info("Cut " .. node.name .. " to clipboard")
  end
  if callback then
    callback()
  end
end

M.show_debug_info = function(state)
  print(vim.inspect(state))
end

---Pastes all items from the clipboard to the current directory.
---@param state table The state of the source
---@param callback function The callback to call when the command is done. Called with the parent node as the argument.
M.paste_from_clipboard = function(state, callback)
  if state.clipboard then
    local at_node = state.tree:get_node()
    local folder = at_node:get_id()
    if at_node.type == "file" then
      folder = at_node:get_parent_id()
    end

    -- Convert to list so to make it easier to pop items from the stack.
    local clipboard_list = {}
    for _, item in pairs(state.clipboard) do
      table.insert(clipboard_list, item)
    end
    state.clipboard = nil
    local handle_next_paste, paste_complete

    paste_complete = function(source, destination)
      if callback then
        -- open the folder so the user can see the new files
        local node = state.tree:get_node(folder)
        if not node then
          log.warn("Could not find node for " .. folder)
        end
        callback(node, destination)
      end
      local next_item = table.remove(clipboard_list)
      if next_item then
        handle_next_paste(next_item)
      end
    end

    handle_next_paste = function(item)
      if item.action == "copy" then
        fs_actions.copy_node(
          item.node.path,
          folder .. utils.path_separator .. item.node.name,
          paste_complete
        )
      elseif item.action == "cut" then
        fs_actions.move_node(
          item.node.path,
          folder .. utils.path_separator .. item.node.name,
          paste_complete
        )
      end
    end

    local next_item = table.remove(clipboard_list)
    if next_item then
      handle_next_paste(next_item)
    end
  end
end

---Copies a node to a new location, using typed input.
---@param state table The state of the source
---@param callback function The callback to call when the command is done. Called with the parent node as the argument.
M.copy = function(state, callback)
  local node = state.tree:get_node()
  fs_actions.copy_node(node.path, nil, callback)
end

---Moves a node to a new location, using typed input.
---@param state table The state of the source
---@param callback function The callback to call when the command is done. Called with the parent node as the argument.
M.move = function(state, callback)
  local node = state.tree:get_node()
  fs_actions.move_node(node.path, nil, callback)
end

M.delete = function(state, callback)
  local tree = state.tree
  local node = tree:get_node()

  fs_actions.delete_node(node.path, callback)
end

---Open file or directory
---@param state table The state of the source
---@param open_cmd string The vim command to use to open the file
---@param toggle_directory function The function to call to toggle a directory
---open/closed
local open_with_cmd = function(state, open_cmd, toggle_directory)
  local tree = state.tree
  local success, node = pcall(tree.get_node, tree)
  if not (success and node) then
    log.debug("Could not get node.")
    return
  end
  if node.type == "directory" then
    if toggle_directory then
      toggle_directory(node)
    elseif node:has_children() then
      local updated = false
      if node:is_expanded() then
        updated = node:collapse()
      else
        updated = node:expand()
      end
      if updated then
        tree:render()
      end
    end
    return nil
  else
    local path = node:get_id()
    utils.open_file(state, path, open_cmd)
  end
end

---Open file or directory in the closest window
---@param state table The state of the source
---@param toggle_directory function The function to call to toggle a directory
---open/closed
M.open = function(state, toggle_directory)
  open_with_cmd(state, "e", toggle_directory)
end

---Open file or directory in a split of the closest window
---@param state table The state of the source
---@param toggle_directory function The function to call to toggle a directory
---open/closed
M.open_split = function(state, toggle_directory)
  open_with_cmd(state, "split", toggle_directory)
end

---Open file or directory in a vertical split of the closest window
---@param state table The state of the source
---@param toggle_directory function The function to call to toggle a directory
---open/closed
M.open_vsplit = function(state, toggle_directory)
  open_with_cmd(state, "vsplit", toggle_directory)
end

M.rename = function(state, callback)
  local tree = state.tree
  local node = tree:get_node()
  fs_actions.rename_node(node.path, callback)
end

---Expands or collapses the current node.
M.toggle_directory = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type ~= "directory" then
    return
  end
  if node.loaded == false then
    -- lazy load this node and pass the children to the renderer
    local children = {}
    renderer.show_nodes(state, children, node:get_id())
  elseif node:has_children() then
    local updated = false
    if node:is_expanded() then
      updated = node:collapse()
    else
      updated = node:expand()
    end
    if updated then
      tree:render()
    else
      tree:render()
    end
  end
end

return M
