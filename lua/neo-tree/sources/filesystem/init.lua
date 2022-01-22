--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local inputs = require("neo-tree.ui.inputs")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")

local M = { name = "filesystem" }

local wrap = function(func)
  return utils.wrap(func, M.name)
end

local get_state = function(tabnr)
  return manager.get_state(M.name, tabnr)
end

-- TODO: DEPRECATED in 1.19, remove in 2.0
-- Leaving this here for now because it was mentioned in the help file.
M.reveal_current_file = function(toggle_if_open)
  log.warn("DEPRECATED: use `neotree.sources.manager.reveal_current_file('filesystem')` instead")
  return manager.reveal_current_file(M.name, toggle_if_open)
end

M.follow = function(callback, force_show)
  log.trace("follow called")
  local path_to_reveal = manager.get_path_to_reveal()
  if not utils.truthy(path_to_reveal) then
    return false
  end

  local state = get_state()
  local window_exists = renderer.window_exists(state)
  if window_exists then
    local node = state.tree and state.tree:get_node()
    if node then
      if node:get_id() == path_to_reveal then
        -- already focused
        return false
      end
    end
  else
    if not force_show then
      return false
    end
  end

  local is_in_path = path_to_reveal:sub(1, #state.path) == state.path
  if not is_in_path then
    return false
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

local navigate_internal = function(path, path_to_reveal, callback)
  log.trace("navigate_internal", path, path_to_reveal)
  local state = get_state()
  state.dirty = false
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
    local follow_file = state.follow_current_file and manager.get_path_to_reveal()
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
    manager.refresh(M.name)
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
    manager.refresh(M.name)
  else
    fs_scan.get_items_async(state, nil, false, function()
      local new_node = state.tree:get_node(node:get_id())
      M.toggle_directory(new_node)
    end)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  --Configure events for before_render
  if config.before_render then
    --convert to new event system
    manager.subscribe(M.name, {
      event = events.BEFORE_RENDER,
      handler = function(state)
        local this_state = get_state()
        if state == this_state then
          config.before_render(this_state)
        end
      end,
    })
  elseif global_config.enable_git_status then
    manager.subscribe(M.name, {
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
    manager.subscribe(M.name, {
      event = events.FS_EVENT,
      handler = wrap(manager.refresh),
    })
  else
    require("neo-tree.sources.filesystem.lib.fs_watch").unwatch_all()
    manager.subscribe(M.name, {
      event = events.VIM_BUFFER_CHANGED,
      handler = wrap(manager.refresh),
    })
  end

  --Configure event handlers for cwd changes
  if config.bind_to_cwd then
    manager.subscribe(M.name, {
      event = events.VIM_DIR_CHANGED,
      handler = wrap(manager.dir_changed),
    })
  end

  --Configure event handlers for lsp diagnostic updates
  if global_config.enable_diagnostics then
    manager.subscribe(M.name, {
      event = events.VIM_DIAGNOSTIC_CHANGED,
      handler = wrap(manager.diagnostics_changed),
    })
  end

  -- Configure event handler for follow_current_file option
  if config.follow_current_file then
    manager.subscribe(M.name, {
      event = events.VIM_BUFFER_ENTER,
      handler = M.follow,
    })
  end
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
