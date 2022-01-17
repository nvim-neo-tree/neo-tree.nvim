--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local events = require("neo-tree.events")
local log = require("neo-tree.log")

local BaseSource = {}
function BaseSource:new()
  local props = {}
  setmetatable(props, self)
  self.__index = self
  return props
end

local default_config = nil
local state_by_tab = {}

local get_state = function(tabnr)
  tabnr = tabnr or vim.api.nvim_get_current_tabpage()
  local state = state_by_tab[tabnr]
  if not state then
    state = utils.table_copy(default_config)
    state.tabnr = tabnr
    state_by_tab[tabnr] = state
  end
  return state
end

local get_path_to_reveal = function()
  if vim.bo.filetype == "neo-tree" then
    return nil
  end
  local path = vim.fn.expand("%:p")
  if not path or path == "" or path:match("term://") then
    return nil
  end
  return path
end

BaseSource.subscribe = function(event)
  local state = get_state()
  if not state.subscriptions then
    state.subscriptions = {}
  end
  state.subscriptions[event] = true
  events.subscribe(event)
end

BaseSource.unsubscribe = function(event, state)
  state = state or get_state()
  if state.subscriptions then
    state.subscriptions[event] = false
  end
  events.unsubscribe(event)
end

BaseSource.close = function()
  local state = get_state()
  return renderer.close(state)
end

---Redraws the tree with updated diagnostics without scanning the filesystem again.
BaseSource.diagnostics_changed = function(args)
  local state = get_state()
  args = args or {}
  state.diagnostics_lookup = args.diagnostics_lookup
  if renderer.window_exists(state) then
    state.tree:render()
  end
end

---Called by autocmds when the cwd dir is changed. This will change the root.
BaseSource.dir_changed = function()
  local state = get_state()
  local cwd = vim.fn.getcwd()
  if state.path and cwd == state.path then
    return
  end
  if state.path and renderer.window_exists(state) then
    BaseSource.navigate(cwd)
  end
end

BaseSource.dispose = function(tabnr)
  local state = get_state(tabnr)
  fs_scan.stop_watchers(state)
  renderer.close(state)
  for event, subscribed in pairs(state.subscriptions) do
    if subscribed then
      unsubscribe(event, state)
    end
  end
  state_by_tab[state.tabnr] = nil
end

BaseSource.float = function()
  local state = get_state()
  state.force_float = true
  local path_to_reveal = get_path_to_reveal()
  BaseSource.navigate(state.path, path_to_reveal)
end

---Focus the window, opening it if it is not already open.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
BaseSource.focus = function(path_to_reveal, callback)
  local state = get_state()
  if path_to_reveal then
    BaseSource.navigate(state.path, path_to_reveal, callback)
  else
    if renderer.window_exists(state) then
      vim.api.nvim_set_current_win(state.winid)
    else
      BaseSource.navigate(state.path, nil, callback)
    end
  end
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
BaseSource.navigate = function(path, path_to_reveal, callback)
  local state = get_state()
  log.error(state.name .. ".navigate() must be overwritten!")
end

BaseSource.reveal_current_file = function(toggle_if_open)
  local state = get_state()
  log.error(state.name .. ".reveal_current_file() must be overwritten!")
end

---Redraws the tree without loading items again. Use this after
-- making changes to the nodes that would affect how their components are
-- rendered.
BaseSource.redraw = function()
  local state = get_state()
  if renderer.window_exists(state) then
    state.tree:render()
  end
end

---Refreshes the tree by loading the items again.
BaseSource.refresh = function(callback)
  local state = get_state()
  if state.path and renderer.window_exists(state) then
    if type(callback) ~= "function" then
      callback = nil
    end
    BaseSource.navigate(state.path, nil, callback)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
BaseSource.setup = function(config, global_config)
  default_config = config
  log.error(state.name .. ".setup() must be overwritten!")
end

---Opens the tree and displays the current path or cwd.
---@param callback function Callback to call after the items are loaded.
BaseSource.show = function(callback)
  local state = get_state()
  BaseSource.navigate(state.path, nil, callback)
end

return BaseSource
