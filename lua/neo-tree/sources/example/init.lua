--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")

local M = {}
local default_config = nil
local state_by_tab = {}

local get_state = function()
  local tabnr = vim.api.nvim_get_current_tabpage()
  local state = state_by_tab[tabnr]
  if not state then
    state = utils.table_copy(default_config)
    state.tabnr = tabnr
    state_by_tab[tabnr] = state
  end
  return state
end

M.close = function()
  local state = get_state()
  return renderer.close(state)
end

M.float = function()
  local state = get_state()
  state.force_float = true
  M.navigate(state.path)
end

M.focus = function()
  local state = get_state()
  if renderer.window_exists(state) then
    vim.api.nvim_set_current_win(state.winid)
  else
    M.navigate(state.path)
  end
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(path)
  local state = get_state()
  local path_changed = false
  if path == nil then
    path = vim.fn.getcwd()
  end
  if path ~= state.path then
    state.path = path
    path_changed = true
  end
  -- Do something useful here to get items
  local items = {
    {
      id = "1",
      name = "root",
      children = {
        {
          id = "1.1",
          name = "child1",
          children = {
            {
              id = "1.1.1",
              name = "child1.1",
            },
            {
              id = "1.1.2",
              name = "child1.2",
            },
          },
        },
      },
    },
  }
  renderer.show_nodes(state, items)
end

---Redraws the tree without scanning the filesystem again. Use this after
-- making changes to the nodes that would affect how their components are
-- rendered.
M.redraw = function()
  local state = get_state()
  if renderer.window_exists(state) then
    state.tree:render()
  end
end

---Refreshes the tree by scanning the filesystem again.
M.refresh = function()
  local state = get_state()
  if state.path and renderer.window_exists(state) then
    M.navigate(state.path)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config)
  if default_config == nil then
    default_config = config
  end
end

---Opens the tree and displays the current path or cwd.
---@param callback function Callback to call after the items are loaded.
M.show = function(callback)
  local state = get_state()
  M.navigate(state.path)
end

---Expands or collapses the current node.
M.toggle_directory = function(node)
  local state = get_state()
  local tree = state.tree
  if not node then
    node = tree:get_node()
  end
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
