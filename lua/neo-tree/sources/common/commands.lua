--This file should contain all commands meant to be used by mappings.

local vim = vim
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")

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

---Marks node as copied, so that it can be pasted somewhere else.
M.copy_to_clipboard = function(state, callback)
  local node = state.tree:get_node()
  state.clipboard = state.clipboard or {}
  local existing = state.clipboard[node.id]
  if existing and existing.action == "copy" then
    state.clipboard[node.id] = nil
  else
    state.clipboard[node.id] = { action = "copy", node = node }
    print("Copied " .. node.name .. " to clipboard")
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
    print("Cut " .. node.name .. " to clipboard")
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
          print("Could not find node for " .. folder)
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

M.delete = function(state, callback)
  local tree = state.tree
  local node = tree:get_node()

  fs_actions.delete_node(node.path, callback)
end

---Open file or directory
---@param state table The state of the source
---@param open_cmd string The vimcommand to use to open the file
---@param toggle_directory function The function to call to toggle a directory
---open/closed
local open_with_cmd = function(state, open_cmd, toggle_directory)
  local tree = state.tree
  local node = tree:get_node()
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
    -- use last window if possible
    local suitable_window_found = false
    local nt = require("neo-tree")
    if nt.config.open_files_in_last_window then
      local prior_window = nt.get_prior_window()
      if prior_window > 0 then
        local success = pcall(vim.api.nvim_set_current_win, prior_window)
        if success then
          suitable_window_found = true
        end
      end
    end
    -- find a suitable window to open the file in
    if not suitable_window_found then
      if state.window.position == "right" then
        vim.cmd("wincmd t")
      else
        vim.cmd("wincmd w")
      end
    end
    local attempts = 0
    while attempts < 4 and vim.bo.filetype == "neo-tree" do
      attempts = attempts + 1
      vim.cmd("wincmd w")
    end
    -- TODO: make this configurable, see issue #43
    if vim.bo.filetype == "neo-tree" then
      -- Neo-tree must be the only window, restore it's status as a sidebar
      local winid = vim.api.nvim_get_current_win()
      local width = utils.get_value(state, "window.width", 40)
      vim.cmd("vsplit " .. node:get_id())
      vim.api.nvim_win_set_width(winid, width)
    else
      vim.cmd(open_cmd .. " " .. node:get_id())
    end
    local events = require("neo-tree.events")
    events.fire_event(events.FILE_OPENED, node:get_id())
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

return M
