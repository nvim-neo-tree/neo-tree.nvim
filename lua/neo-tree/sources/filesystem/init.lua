--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local inputs = require("neo-tree.ui.inputs")
local events = require("neo-tree.events")
local log = require("neo-tree.log")

local M = {}
local default_config = nil
local state_by_tab = {}

local set_default_config = function(config)
  default_config = config
  for tabnr, tab_config in pairs(state_by_tab) do
    state_by_tab[tabnr] = utils.table_merge(tab_config, config)
  end
end

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

local expand_to_root
expand_to_root = function(tree, from_node)
  local parent_id = from_node:get_parent_id()
  if not parent_id then
    return
  end
  local parent_node = tree:get_node(parent_id)
  if parent_node then
    parent_node:expand()
    expand_to_root(tree, parent_node)
  end
end

local get_path_to_reveal = function()
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

local subscribe = function(event)
  local state = get_state()
  if not state.subscriptions then
    state.subscriptions = {}
  end
  if not utils.truthy(event.id) then
    event.id = state.name .. "." .. event.event
  end
  log.trace("subscribing to event: " .. event.id)
  state.subscriptions[event] = true
  events.subscribe(event)
end

local unsubscribe = function(event, state)
  state = state or get_state()
  if type(event) ~= "table" then
    error("unsubscribe: event must be a table")
  end
  log.trace("unsubscribing to event: " .. event.id or event.event)
  if state.subscriptions then
    for sub, _ in pairs(state.subscriptions) do
      if sub.event == event.event and sub.id == event.id then
        state.subscriptions[sub] = false
        events.unsubscribe(sub)
      end
    end
  end
  events.unsubscribe(event)
end

local unsubscribe_all = function(state)
  state = state or get_state()
  if state.subscriptions then
    for event, subscribed in pairs(state.subscriptions) do
      if subscribed then
        unsubscribe(event, state)
      end
    end
  end
  state.subscriptions = {}
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

---Called by autocmds when the cwd dir is changed. This will change the root.
M.dir_changed = function()
  local state = get_state()
  local cwd = vim.fn.getcwd()
  if state.path and cwd == state.path then
    return
  end
  if state.path and renderer.window_exists(state) then
    M.navigate(cwd)
  end
end

M.dispose = function(tabnr)
  local state = get_state(tabnr)
  log.trace(state.name, " disposing of tab: ", tabnr)
  fs_scan.stop_watchers(state)
  unsubscribe_all(state)
  renderer.close(state)
  state_by_tab[state.tabnr] = nil
end

M.float = function()
  local state = get_state()
  state.force_float = true
  local path_to_reveal = get_path_to_reveal()
  M.navigate(state.path, path_to_reveal)
end

M.follow = function(callback, force_show)
  log.trace("follow called")
  local path_to_reveal = get_path_to_reveal()
  if not utils.truthy(path_to_reveal) then
    return false
  end
  local state = get_state()
  if not force_show and not renderer.window_exists(state) then
    return false
  end
  local is_in_path = path_to_reveal:sub(1, #state.path) == state.path
  if not is_in_path then
    return false
  end
  local node = state.tree and state.tree:get_node()
  if node then
    if node:get_id() == path_to_reveal then
      -- already focused
      return false
    end
  end

  log.debug("follow file: ", path_to_reveal)
  local show_only_explicitly_opened = function()
    local eod = state.explicitly_opened_directories or {}
    local expanded_nodes = renderer.get_expanded_nodes(state.tree)
    local state_changed = false
    for _, id in ipairs(expanded_nodes) do
      local is_explicit = eod[id]
      if not is_explicit then
        local is_in_path = path_to_reveal:sub(1, #id) == id
        if is_in_path then
          is_explicit = true
        end
      end
      if not is_explicit then
        local node = state.tree:get_node(id)
        if node then
          node:collapse()
          state_changed = true
        end
      end
      if state_changed then
        state.tree:render()
      end
    end
  end

  fs_scan.get_items_async(state, nil, path_to_reveal, function()
    local event = {
      event = events.AFTER_RENDER,
      id = "neo-tree-follow:" .. tostring(state),
    }
    events.unsubscribe(event) -- if there is a prior event waiting, replace it
    event.handler = function(arg)
      if arg ~= state then
        return -- this is not our event
      end
      event.cancelled = true
      log.trace(event.id .. ": handler called")
      show_only_explicitly_opened()
      renderer.focus_node(state, path_to_reveal, true)
      if type(callback) == "function" then
        callback()
      end
    end

    events.subscribe(event)
  end)
  return true
end

---Focus the window, opening it if it is not already open.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.focus = function(path_to_reveal, callback)
  local state = get_state()
  if path_to_reveal then
    M.navigate(state.path, path_to_reveal, callback)
  else
    if renderer.window_exists(state) then
      vim.api.nvim_set_current_win(state.winid)
    else
      M.navigate(state.path, nil, callback)
    end
  end
end

local navigate_internal = function(path, path_to_reveal, callback)
  log.trace("navigate_internal", path, path_to_reveal)
  local state = get_state()
  local pos = utils.get_value(state, "window.position", "left")
  local path_changed = false
  if path == nil then
    path = vim.fn.getcwd()
  end
  if path ~= state.path then
    state.path = path
    path_changed = true
  end

  if path_to_reveal then
    fs_scan.get_items_async(state, nil, path_to_reveal, function()
      renderer.focus_node(state, path_to_reveal)
      if callback then
        callback()
      end
      state.in_navigate = false
    end)
  else
    local follow_file = state.follow_current_file and get_path_to_reveal()
    if utils.truthy(follow_file) then
      M.follow(function()
        if callback then
          callback()
        end
        state.in_navigate = false
      end, true)
    else
      local previously_focused = nil
      if state.tree and renderer.is_window_valid(state.winid) then
        local node = state.tree:get_node()
        if node then
          -- keep the current node selected
          previously_focused = node:get_id()
        end
      end
      fs_scan.get_items_async(state, nil, nil, function()
        local current_winid = vim.api.nvim_get_current_win()
        if path_changed and current_winid == state.winid and previously_focused then
          local currently_focused = state.tree:get_node():get_id()
          if currently_focused ~= previously_focused then
            renderer.focus_node(state, previously_focused, false)
          end
        end
        if callback then
          callback()
        end
        state.in_navigate = false
      end)
    end
  end

  if path_changed then
    if state.bind_to_cwd then
      vim.api.nvim_command("tcd " .. path)
    end
  end
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.navigate = function(path, path_to_reveal, callback)
  log.trace("navigate", path, path_to_reveal)
  local state = get_state()
  state.in_navigate = true
  utils.debounce("filesystem_navigate", function()
    navigate_internal(path, path_to_reveal, callback)
  end, 100)
end

M.reveal_current_file = function(toggle_if_open)
  log.trace("Revealing current file")
  if toggle_if_open then
    if M.close() then
      -- It was open, and now it's not.
      return
    end
  end
  local state = get_state()
  require("neo-tree").close_all_except("filesystem")
  local path = get_path_to_reveal()
  if not path then
    M.focus()
    return
  end
  local cwd = state.path
  if cwd == nil then
    cwd = vim.fn.getcwd()
  end
  if string.sub(path, 1, string.len(cwd)) ~= cwd then
    cwd, _ = utils.split_path(path)
    inputs.confirm("File not in cwd. Change cwd to " .. cwd .. "?", function(response)
      if response == true then
        state.path = cwd
        M.focus(path)
      end
    end)
    return
  end
  if path then
    if not renderer.focus_node(state, path) then
      M.focus(path)
    end
  end
end

M.reset_search = function(refresh)
  log.trace("reset_search")
  local state = get_state()
  if refresh == nil then
    refresh = true
  end
  if state.open_folders_before_search then
    log.trace("reset_search: open_folders_before_search")
    state.force_open_folders = utils.table_copy(state.open_folders_before_search)
  else
    log.trace("reset_search: why are there no open_folders_before_search?")
    state.force_open_folders = nil
  end
  state.search_pattern = nil
  state.open_folders_before_search = nil
  if refresh then
    M.refresh()
  end
end

M.show_new_children = function(node_or_path)
  local state = get_state()
  local node = node_or_path
  if node_or_path == nil then
    node = state.tree:get_node()
  elseif type(node_or_path) == "string" then
    node = state.tree:get_node(node_or_path)
    if node == nil then
      local parent_path, _ = utils.split_path(node_or_path)
      node = state.tree:get_node(parent_path)
    end
  else
    node = node_or_path
  end

  if node.type ~= "directory" then
    return
  end

  if node:is_expanded() then
    M.refresh()
  else
    fs_scan.get_items_async(state, nil, false, function()
      local new_node = state.tree:get_node(node:get_id())
      M.toggle_directory(new_node)
    end)
  end
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
M.refresh = function(callback)
  log.trace("filesystem refresh")
  local state = get_state()
  if state.in_navigate or state.in_show_nodes then
    return
  end
  if state.path and renderer.window_exists(state) then
    if type(callback) ~= "function" then
      callback = nil
    end
    M.navigate(state.path, nil, callback)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  set_default_config(config)
  log.debug("filesystem setup", config)
  local state = get_state()
  unsubscribe_all(state)

  --Configure events for before_render
  if config.before_render then
    --convert to new event system
    subscribe({
      event = events.BEFORE_RENDER,
      handler = function(state)
        local this_state = get_state()
        if state == this_state then
          config.before_render(this_state)
        end
      end,
    })
  elseif global_config.enable_git_status then
    subscribe({
      event = events.BEFORE_RENDER,
      handler = function(state)
        local this_state = get_state()
        if state == this_state then
          state.git_status_lookup = utils.get_git_status()
        end
      end,
    })
  end

  --Configure event handlers for file changes
  if config.use_libuv_file_watcher then
    subscribe({
      event = events.FS_EVENT,
      handler = M.refresh,
    })
  else
    require("neo-tree.sources.filesystem.lib.fs_watch").unwatch_all()
    subscribe({
      event = events.VIM_BUFFER_CHANGED,
      handler = M.refresh,
    })
  end

  --Configure event handlers for cwd changes
  if default_config.bind_to_cwd then
    subscribe({
      event = events.VIM_DIR_CHANGED,
      handler = M.dir_changed,
    })
  end

  --Configure event handlers for lsp diagnostic updates
  if global_config.enable_diagnostics then
    subscribe({
      event = events.VIM_DIAGNOSTIC_CHANGED,
      handler = M.diagnostics_changed,
    })
  end

  -- Configure event handler for follow_current_file option
  if config.follow_current_file then
    subscribe({
      event = events.VIM_BUFFER_ENTER,
      handler = M.follow,
    })
  end

  --Dispose ourselves if the tab closes
  subscribe({
    event = events.VIM_TAB_CLOSED,
    handler = function(args)
      local tabnr = tonumber(args.afile)
      if tabnr then
        log.debug("VIM_TAB_CLOSED: disposing state for tab", tabnr)
        M.dispose(tabnr)
      else
        log.error("VIM_TAB_CLOSED: no tab number found in args.afile")
      end
    end,
  })
end

---Opens the tree and displays the current path or cwd.
---@param callback function Callback to call after the items are loaded.
M.show = function(callback)
  local state = get_state()
  M.navigate(state.path, nil, callback)
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
  state.explicitly_opened_directories = state.explicitly_opened_directories or {}
  if node.loaded == false then
    state.explicitly_opened_directories[node:get_id()] = true
    fs_scan.get_items_async(state, node.id, true)
  elseif node:has_children() then
    local updated = false
    if node:is_expanded() then
      updated = node:collapse()
      state.explicitly_opened_directories[node:get_id()] = false
    else
      updated = node:expand()
      state.explicitly_opened_directories[node:get_id()] = true
    end
    if updated then
      tree:render()
    end
  end
end

return M
