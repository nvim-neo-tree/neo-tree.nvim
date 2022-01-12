--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local items = require("neo-tree.sources.git_status.lib.items")
local events = require("neo-tree.events")

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

---Redraws the tree with updated diagnostics without scanning the filesystem again.
M.diagnostics_changed = function(args)
  local state = get_state()
  args = args or {}
  state.diagnostics_lookup = args.diagnostics_lookup
  if renderer.window_exists(state) then
    state.tree:render()
  end
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
  items.get_git_status(state)
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

local refresh_internal = function()
  for _, state in pairs(state_by_tab) do
    if state.path and renderer.window_exists(state) then
      items.get_git_status(state)
    end
  end
end

M.refresh = function()
  utils.debounce("git_status_refresh", refresh_internal, 500)
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  default_config = config

  if config.before_render then
    --convert to new event system
    events.subscribe({
      event = events.BEFORE_RENDER,
      handler = config.before_render,
      id = config.name .. ".config.before_render",
    })
  else
    events.unsubscribe({
      event = events.BEFORE_RENDER,
      id = config.name .. ".config.before_render",
    })
  end

  events.subscribe({
    event = events.VIM_BUFFER_CHANGED,
    handler = M.refresh,
    id = "git_status." .. events.VIM_BUFFER_CHANGED,
  })

  if default_config.bind_to_cwd then
    events.subscribe({
      event = events.VIM_DIR_CHANGED,
      handler = M.refresh,
      id = "git_status." .. events.VIM_DIR_CHANGED,
    })
  end

  if global_config.enable_diagnostics then
    events.subscribe({
      event = events.VIM_DIAGNOSTIC_CHANGED,
      handler = M.diagnostics_changed,
      id = "git_status." .. events.VIM_DIAGNOSTIC_CHANGED,
    })
  end
end

---Opens the tree and displays the current path or cwd.
M.show = function()
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
