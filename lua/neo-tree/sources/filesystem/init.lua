--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.fs_scan")
local fs_actions = require("neo-tree.sources.filesystem.fs_actions")
local renderer = require("neo-tree.renderer")

local M = {}
local myState = nil

---Called by autocmds when the cwd dir is changed. This will change the root.
M.dir_changed = function()
  local cwd = vim.fn.getcwd()
  if myState.path and cwd == myState.path then
    return
  end
  if myState.path and renderer.window_exists(myState) then
    M.navigate(cwd)
  end
end

---Naviagte to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(path)
  if path == nil then
    path = vim.fn.getcwd()
  end
  myState.path = path
  fs_scan.getItemsAsync(myState)
  if myState.bind_to_cwd then
    vim.api.nvim_command("tcd " .. path)
  end
end

M.show_new_children = function(node)
  if not node then
    node = myState.tree:get_node()
  end
  if node.type ~= 'directory' then
    return
  end

  if node:is_expanded() then
    M.refresh()
  else
    fs_scan.getItemsAsync(myState, nil, false, function()
      local new_node = myState.tree:get_node(node:get_id())
      M.toggle_directory(new_node)
    end)
  end
end

---Redraws the tree without scanning the filesystem again. Use this after
-- making changes to the nodes that would affect how their components are
-- rendered.
M.redraw = function()
  if renderer.window_exists(myState) then
    myState.tree:render()
  end
end

---Refreshes the tree by scanning the filesystem again.
M.refresh = function()
  if myState.path and renderer.window_exists(myState) then
    M.navigate(myState.path)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config)
  if myState == nil then
    myState = utils.tableCopy(config)
    myState.commands = require("neo-tree.sources.filesystem.commands")
    local autocmds = {}
    local refresh_cmd = ":lua require('neo-tree.sources.filesystem').refresh()"
    table.insert(autocmds, "augroup neotreefilesystem")
    table.insert(autocmds, "autocmd!")
    table.insert(autocmds, "autocmd BufWritePost * " .. refresh_cmd)
    table.insert(autocmds, "autocmd BufDelete * " .. refresh_cmd)
    if myState.bind_to_cwd then
      table.insert(autocmds, "autocmd DirChanged * :lua require('neo-tree.sources.filesystem').dir_changed()")
    end
    table.insert(autocmds, "augroup END")
    vim.cmd(table.concat(autocmds, "\n"))
  end
end

---Opens the tree and displays the current path or cwd.
M.show = function()
  M.navigate(myState.path)
end

---Expands or collapses the current node.
M.toggle_directory = function (node)
  local tree = myState.tree
  if not node then
    node = tree:get_node()
  end
  if node.type ~= 'directory' then
    return
  end
  if node.loaded == false then
    fs_scan.getItemsAsync(myState, node.id, true)
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
