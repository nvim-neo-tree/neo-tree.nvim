--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local inputs = require("neo-tree.ui.inputs")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")

local M = {}
local source_data = {}
local default_configs = {}

local get_source_data = function(source_name)
  if source_name == nil then
    error("get_source_data: source_name cannot be nil")
  end
  local sd = source_data[source_name]
  if sd then
    return sd
  end
  sd = {
    name = source_name,
    state_by_tab = {},
    subscriptions = {},
  }
  source_data[source_name] = sd
  return sd
end

local function create_state(tabnr, sd)
  local default_config = default_configs[sd.name]
  local state = utils.table_copy(default_config)
  state.tabnr = tabnr
  state.dirty = true
  state.position = {
    save = function()
      if state.tree and renderer.window_exists(state) then
        local node = state.tree:get_node()
        if node then
          state.position.node_id = node:get_id()
        end
      end
      -- Only need to restore the cursor state once per save, comes
      -- into play when some actions fire multiple times per "iteration"
      -- within the scope of where we need to perform the restore operation
      state.position.is.restorable = true
    end,
    set = function(node_id)
      if not type(node_id) == "string" and node_id > "" then
        return
      end
      state.position.node_id = node_id
      state.position.is.restorable = true
    end,
    restore = function()
      if not state.position.node_id then
        return
      end
      if state.position.is.restorable then
        renderer.focus_node(state, state.position.node_id, true)
      end
      state.position.is.restorable = false
    end,
    is = { restorable = true },
  }
  return state
end

---For use in tests only, completely resets the state of all sources.
---This closes all windows as well since they would be broken by this action.
M._clear_state = function()
  fs_watch.unwatch_all()
  renderer.close_all_floating_windows()
  for _, data in pairs(source_data) do
    for _, state in pairs(data.state_by_tab) do
      renderer.close(state)
    end
  end
  source_data = {}
end

M.set_default_config = function(source_name, config)
  if source_name == nil then
    error("set_default_config: source_name cannot be nil")
  end
  default_configs[source_name] = config
  local sd = get_source_data(source_name)
  for tabnr, tab_config in pairs(sd.state_by_tab) do
    sd.state_by_tab[tabnr] = utils.table_merge(tab_config, config)
  end
end

M.get_state = function(source_name, tabnr)
  if source_name == nil then
    error("get_state: source_name cannot be nil")
  end
  tabnr = tabnr or vim.api.nvim_get_current_tabpage()
  local sd = get_source_data(source_name)
  local state = sd.state_by_tab[tabnr]
  if state then
    return state
  end
  sd.state_by_tab[tabnr] = create_state(tabnr, sd)
  return sd.state_by_tab[tabnr]
end

M.get_path_to_reveal = function()
  local win_id = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(win_id)
  if cfg.relative > "" or cfg.external then
    -- floating window, ignore
    return nil
  end
  if vim.bo.filetype == "neo-tree" then
    return nil
  end
  local path = vim.fn.expand("%:p")
  if not utils.truthy(path) or path:match("term://") then
    return nil
  end
  return path
end

M.subscribe = function(source_name, event)
  if source_name == nil then
    error("subscribe: source_name cannot be nil")
  end
  local sd = get_source_data(source_name)
  if not sd.subscriptions then
    sd.subscriptions = {}
  end
  if not utils.truthy(event.id) then
    event.id = sd.name .. "." .. event.event
  end
  log.trace("subscribing to event: " .. event.id)
  sd.subscriptions[event] = true
  events.subscribe(event)
end

M.unsubscribe = function(source_name, event)
  if source_name == nil then
    error("unsubscribe: source_name cannot be nil")
  end
  local sd = get_source_data(source_name)
  log.trace("unsubscribing to event: " .. event.id or event.event)
  if sd.subscriptions then
    for sub, _ in pairs(sd.subscriptions) do
      if sub.event == event.event and sub.id == event.id then
        sd.subscriptions[sub] = false
        events.unsubscribe(sub)
      end
    end
  end
  events.unsubscribe(event)
end

M.unsubscribe_all = function(source_name)
  if source_name == nil then
    error("unsubscribe_all: source_name cannot be nil")
  end
  local sd = get_source_data(source_name)
  if sd.subscriptions then
    for event, subscribed in pairs(sd.subscriptions) do
      if subscribed then
        events.unsubscribe(event)
      end
    end
  end
  sd.subscriptions = {}
end

M.close = function(source_name)
  local state = M.get_state(source_name)
  return renderer.close(state)
end

---Redraws the tree with updated diagnostics without scanning the filesystem again.
M.diagnostics_changed = function(source_name, args)
  local state = M.get_state(source_name)
  args = args or {}
  state.diagnostics_lookup = args.diagnostics_lookup
  if renderer.window_exists(state) then
    state.tree:render()
  end
end

---Called by autocmds when the cwd dir is changed. This will change the root.
M.dir_changed = function(source_name)
  local state = M.get_state(source_name)
  local cwd = vim.fn.getcwd()
  if state.path and cwd == state.path then
    return
  end
  if state.path and renderer.window_exists(state) then
    M.navigate(source_name, cwd)
  else
    state.path = cwd
    state.dirty = true
  end
end

M.dispose = function(source_name, tabnr)
  local sources
  if type(source_name) == "string" then
    sources = { source_name }
  else
    sources = {}
    for n, _ in pairs(source_data) do
      table.insert(sources, n)
    end
  end
  for _, sname in ipairs(sources) do
    local state = M.get_state(sname, tabnr)
    log.trace(state.name, " disposing of tab: ", tabnr)
    fs_scan.stop_watchers(state)
    renderer.close(state)
    source_data[sname].state_by_tab[state.tabnr] = nil
  end
end

M.float = function(source_name)
  local state = M.get_state(source_name)
  state.force_float = true
  local path_to_reveal = M.get_path_to_reveal()
  M.navigate(source_name, state.path, path_to_reveal)
end

---Focus the window, opening it if it is not already open.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.focus = function(source_name, path_to_reveal, callback)
  local state = M.get_state(source_name)
  if path_to_reveal then
    M.navigate(source_name, state.path, path_to_reveal, callback)
  else
    if not state.dirty and renderer.window_exists(state) then
      vim.api.nvim_set_current_win(state.winid)
    else
      M.navigate(source_name, state.path, nil, callback)
    end
  end
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.navigate = function(source_name, path, path_to_reveal, callback)
  log.trace("navigate", source_name, path, path_to_reveal)
  require("neo-tree.sources." .. source_name).navigate(path, path_to_reveal, callback)
end

M.reveal_current_file = function(source_name)
  log.trace("Revealing current file")
  local state = M.get_state(source_name)

  -- When events trigger that try to restore the position of the cursor in the tree window,
  -- we want them to ignore this "iteration" as the user is trying to explicitly focus a
  -- (potentially) different position/node
  state.position.is.restorable = false

  require("neo-tree").close_all_except(source_name)
  local path = M.get_path_to_reveal()
  if not path then
    M.focus(source_name)
    return
  end
  local cwd = state.path
  if cwd == nil then
    cwd = vim.fn.getcwd()
  end
  if not utils.is_subpath(cwd, path) then
    cwd, _ = utils.split_path(path)
    inputs.confirm("File not in cwd. Change cwd to " .. cwd .. "?", function(response)
      if response == true then
        state.path = cwd
        M.focus(source_name, path)
      else
        M.focus(source_name)
      end
    end)
    return
  end
  if path then
    if not renderer.focus_node(state, path) then
      M.focus(source_name, path)
    end
  end
end

---Redraws the tree without scanning the filesystem again. Use this after
-- making changes to the nodes that would affect how their components are
-- rendered.
M.redraw = function(source_name)
  local state = M.get_state(source_name)
  if state.tree and renderer.window_exists(state) then
    state.tree:render()
  end
end

---Refreshes the tree by scanning the filesystem again.
M.refresh = function(source_name, callback)
  local current_tabnr = vim.api.nvim_get_current_tabpage()
  local sd = get_source_data(source_name)
  for _, state in pairs(sd.state_by_tab) do
    if state.tabnr == current_tabnr and state.path and renderer.window_exists(state) then
      log.trace(source_name, " refresh")
      if type(callback) ~= "function" then
        callback = nil
      end
      M.navigate(source_name, state.path, nil, callback)
    else
      state.dirty = true
    end
  end
end

M.validate_source = function(source_name, module)
  if source_name == nil then
    error("register_source: source_name cannot be nil")
  end
  if module == nil then
    error("register_source: module cannot be nil")
  end
  if type(module) ~= "table" then
    error("register_source: module must be a table")
  end
  local required_functions = {
    "navigate",
    "setup",
  }
  for _, name in ipairs(required_functions) do
    if type(module[name]) ~= "function" then
      error("Source " .. source_name .. " must have a " .. name .. " function")
    end
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(source_name, config, global_config)
  log.debug(source_name, " setup ", config)
  M.unsubscribe_all(source_name)
  M.set_default_config(source_name, config)
  local module = require("neo-tree.sources." .. source_name)
  local success, err = pcall(M.validate_source, source_name, module)
  if success then
    success, err = pcall(module.setup, config, global_config)
    if success then
      get_source_data(source_name).module = module
      --Dispose ourselves if the tab closes
      M.subscribe(source_name, {
        event = events.VIM_TAB_CLOSED,
        handler = function(args)
          local tabnr = tonumber(args.afile)
          log.debug("VIM_TAB_CLOSED: disposing state for tab", tabnr)
          M.dispose(source_name, tabnr)
        end,
      })
    else
      log.error("Source " .. source_name .. " setup failed: " .. err)
    end
  else
    log.error("Source " .. source_name .. " is invalid: " .. err)
  end
end

---Opens the tree and displays the current path or cwd, without focusing it.
M.show = function(source_name)
  local state = M.get_state(source_name)
  if not renderer.window_exists(state) then
    local current_win = vim.api.nvim_get_current_win()
    M.navigate(source_name, state.path, nil, function()
      vim.api.nvim_set_current_win(current_win)
    end)
  end
end

return M
