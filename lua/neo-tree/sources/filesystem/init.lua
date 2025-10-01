--This file should have all functions that are in the public api and either set
--or read the state of this source.

local utils = require("neo-tree.utils")
local _compat = require("neo-tree.utils._compat")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local git = require("neo-tree.git")
local glob = require("neo-tree.sources.filesystem.lib.globtopattern")

---@class neotree.sources.filesystem : neotree.Source
local M = {
  name = "filesystem",
  display_name = " 󰉓 Files ",
}

local wrap = function(func)
  return utils.wrap(func, M.name)
end

---@return neotree.sources.filesystem.State
local get_state = function(tabid)
  return manager.get_state(M.name, tabid) --[[@as neotree.sources.filesystem.State]]
end

local follow_internal = function(callback, force_show, async)
  log.trace("follow called")
  local state = get_state()
  if vim.bo.filetype == "neo-tree" or vim.bo.filetype == "neo-tree-popup" then
    return false
  end
  local path_to_reveal = utils.normalize_path(manager.get_path_to_reveal() or "")
  if not utils.truthy(path_to_reveal) then
    return false
  end
  ---@cast path_to_reveal string

  if state.current_position == "float" then
    return false
  end
  if not state.path then
    return false
  end
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

  log.debug("follow file:", path_to_reveal)
  local show_only_explicitly_opened = function()
    state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
    local expanded_nodes = renderer.get_expanded_nodes(state.tree)
    local state_changed = false
    for _, id in ipairs(expanded_nodes) do
      if not state.explicitly_opened_nodes[id] then
        if path_to_reveal:sub(1, #id) == id then
          state.explicitly_opened_nodes[id] = state.follow_current_file.leave_dirs_open
        else
          local node = state.tree:get_node(id)
          if node then
            node:collapse()
            state_changed = true
          end
        end
      end
      if state_changed then
        renderer.redraw(state)
      end
    end
  end

  fs_scan.get_items(state, nil, path_to_reveal, function()
    show_only_explicitly_opened()
    renderer.focus_node(state, path_to_reveal, true)
    if type(callback) == "function" then
      callback()
    end
  end, async)
  return true
end

M.follow = function(callback, force_show)
  if vim.fn.bufname(0) == "COMMIT_EDITMSG" then
    return false
  end
  if utils.is_floating() then
    return false
  end
  utils.debounce("neo-tree-follow", function()
    return follow_internal(callback, force_show)
  end, 100, utils.debounce_strategy.CALL_LAST_ONLY)
end

local fs_stat = (vim.uv or vim.loop).fs_stat

---@param state neotree.sources.filesystem.State
---@param path string?
---@param path_to_reveal string?
---@param callback function?
M._navigate_internal = function(state, path, path_to_reveal, callback, async)
  log.trace("navigate_internal", state.current_position, path, path_to_reveal)
  state.dirty = false
  local is_search = utils.truthy(state.search_pattern)
  local path_changed = false
  if not path and not state.bind_to_cwd then
    path = state.path
  end
  if path == nil then
    log.debug("navigate_internal: path is nil, using cwd")
    path = manager.get_cwd(state)
  end
  path = utils.normalize_path(path)

  -- if path doesn't exist, navigate upwards until it does
  local orig_path = path
  local backed_out = false
  while not fs_stat(path) do
    log.debug("navigate_internal: path", path, "didn't exist, going up a directory")
    backed_out = true
    local parent, _ = utils.split_path(path)
    if not parent then
      break
    end
    path = parent
  end

  if backed_out then
    log.at.warn.format("Root path %s doesn't exist, backing out to %s", orig_path, path)
  end

  if path ~= state.path then
    log.debug("navigate_internal: path changed from", state.path, "to", path)
    state.path = path
    path_changed = true
  end

  if path_to_reveal then
    renderer.position.set(state, path_to_reveal)
    log.debug("navigate_internal: in path_to_reveal, state.position=", state.position.node_id)
    fs_scan.get_items(state, nil, path_to_reveal, callback)
  else
    local is_current = state.current_position == "current"
    local follow_file = state.follow_current_file.enabled
      and not is_search
      and not is_current
      and manager.get_path_to_reveal()
    local handled = false
    if utils.truthy(follow_file) then
      handled = follow_internal(callback, true, async)
    end
    if not handled then
      local success, msg = pcall(renderer.position.save, state)
      if success then
        log.trace("navigate_internal: position saved")
      else
        log.trace("navigate_internal: FAILED to save position:", msg)
      end
      fs_scan.get_items(state, nil, nil, callback, async)
    end
  end

  if path_changed and state.bind_to_cwd then
    manager.set_cwd(state)
  end
  local config = require("neo-tree").config
  if config.enable_git_status and not is_search and config.git_status_async then
    git.status_async(state.path, state.git_base, config.git_status_async_options)
  end
end

---Navigate to the given path.
---@param path string? Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string? Node to focus after the items are loaded.
---@param callback function? Callback to call after the items are loaded.
M.navigate = function(state, path, path_to_reveal, callback, async)
  state._ready = false
  log.trace("navigate", path, path_to_reveal, async)
  utils.debounce("filesystem_navigate", function()
    M._navigate_internal(state, path, path_to_reveal, callback, async)
  end, 100, utils.debounce_strategy.CALL_FIRST_AND_LAST)
end

---@param state neotree.State
M.reset_search = function(state, refresh, open_current_node)
  log.trace("reset_search")
  -- Cancel any pending search
  require("neo-tree.sources.filesystem.lib.filter_external").cancel()
  -- reset search state
  state.fuzzy_finder_mode = nil
  state.use_fzy = nil
  state.fzy_sort_result_scores = nil
  state.sort_function_override = nil

  if refresh == nil then
    refresh = true
  end
  if state.open_folders_before_search then
    state.force_open_folders = vim.deepcopy(state.open_folders_before_search, _compat.noref())
  else
    state.force_open_folders = nil
  end
  state.search_pattern = nil
  state.open_folders_before_search = nil
  if open_current_node then
    local success, node = pcall(state.tree.get_node, state.tree)
    if success and node then
      local path = node:get_id()
      renderer.position.set(state, path)
      if node.type == "directory" then
        path = utils.remove_trailing_slash(path)
        log.trace("opening directory from search: ", path)
        M.navigate(state, nil, path, function()
          pcall(renderer.focus_node, state, path, false)
        end)
      else
        utils.open_file(state, path)
        if
          refresh
          and state.current_position ~= "current"
          and state.current_position ~= "float"
        then
          M.navigate(state, nil, path)
        end
      end
    end
  else
    if refresh then
      M.navigate(state)
    end
  end
end

M.show_new_children = function(state, node_or_path)
  local node = node_or_path
  if node_or_path == nil then
    node = state.tree:get_node()
    node_or_path = node:get_id()
  elseif type(node_or_path) == "string" then
    node = state.tree:get_node(node_or_path)
    if node == nil then
      local parent_path, _ = utils.split_path(node_or_path)
      node = state.tree:get_node(parent_path)
      if node == nil then
        M.navigate(state, nil, node_or_path)
        return
      end
    end
  else
    node = node_or_path
    node_or_path = node:get_id()
  end

  if node.type ~= "directory" then
    return
  end

  M.navigate(state, nil, node_or_path)
end

M.focus_destination_children = function(state, move_from, destination)
  return M.show_new_children(state, destination)
end

---@alias neotree.Config.Cwd "tab"|"window"|"global"

---@class neotree.Config.Filesystem.CwdTarget
---@field sidebar neotree.Config.Cwd?
---@field current neotree.Config.Cwd?

---@class neotree.Config.Filesystem.FilteredItems
---@field visible boolean?
---@field force_visible_in_empty_folder boolean?
---@field children_inherit_highlights boolean?
---@field show_hidden_count boolean?
---@field hide_dotfiles boolean?
---@field hide_gitignored boolean?
---@field hide_ignored boolean?
---@field ignore_files string[]?
---@field hide_hidden boolean?
---@field hide_by_name string[]?
---@field hide_by_pattern string[]?
---@field always_show string[]?
---@field always_show_by_pattern string[]?
---@field never_show string[]?
---@field never_show_by_pattern string[]?

---@alias neotree.Config.Filesystem.FindArgsHandler fun(cmd:string, path:string, search_term:string, args:string[]):string[]

---@class neotree.Config.Filesystem.FollowCurrentFile
---@field enabled boolean?
---@field leave_dirs_open boolean?

---@alias neotree.Config.HijackNetrwBehavior
---|"open_default" # opening a directory opens neo-tree with the default window.position.
---|"open_current" # opening a directory opens neo-tree within the current window.
---|"disabled" # opening a directory opens neo-tree within the current window.

---@class neotree.Config.Filesystem.Renderers : neotree.Config.Renderers

---@class neotree.Config.Filesystem.Window : neotree.Config.Window
---@field fuzzy_finder_mappings neotree.Config.FuzzyFinder.Mappings?

---@alias neotree.Config.Filesystem.AsyncDirectoryScan
---|"auto"
---|"always"
---|"never"

---@alias neotree.Config.Filesystem.ScanMode
---|"shallow"
---|"deep"

---@class (exact) neotree.Config.Filesystem : neotree.Config.Source
---@field async_directory_scan neotree.Config.Filesystem.AsyncDirectoryScan?
---@field scan_mode neotree.Config.Filesystem.ScanMode?
---@field bind_to_cwd boolean?
---@field cwd_target neotree.Config.Filesystem.CwdTarget?
---@field check_gitignore_in_search boolean?
---@field filtered_items neotree.Config.Filesystem.FilteredItems?
---@field find_by_full_path_words boolean?
---@field find_command string?
---@field find_args table<string, string[]>|neotree.Config.Filesystem.FindArgsHandler|nil
---@field group_empty_dirs boolean?
---@field search_limit integer?
---@field follow_current_file neotree.Config.Filesystem.FollowCurrentFile?
---@field hijack_netrw_behavior neotree.Config.HijackNetrwBehavior?
---@field use_libuv_file_watcher boolean?
---@field renderers neotree.Config.Filesystem.Renderers?
---@field window neotree.Config.Filesystem.Window?
---@field enable_git_status boolean?

---Configures the plugin, should be called before the plugin is used.
---@param config neotree.Config.Filesystem Configuration table containing any keys that the user wants to change from the defaults. May be empty to accept default values.
---@param global_config neotree.Config.Base
M.setup = function(config, global_config)
  config.filtered_items = config.filtered_items or {}
  config.enable_git_status = config.enable_git_status or global_config.enable_git_status

  local filtered = config.filtered_items
  if filtered then
    for _, list in ipairs({
      filtered.hide_by_pattern or {},
      filtered.always_show_by_pattern or {},
      filtered.never_show_by_pattern or {},
    }) do
      for i, pattern in ipairs(list) do
        list[i] = glob.globtopattern(pattern)
      end
    end
    for _, key in ipairs({ "hide_by_name", "always_show", "never_show" }) do
      local list = filtered[key]
      if type(list) == "table" then
        filtered[key] = utils.list_to_dict(list)
      end
    end
  end

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
  elseif global_config.enable_git_status and global_config.git_status_async then
    manager.subscribe(M.name, {
      event = events.GIT_STATUS_CHANGED,
      handler = wrap(manager.git_status_changed),
    })
  elseif global_config.enable_git_status then
    manager.subscribe(M.name, {
      event = events.BEFORE_RENDER,
      handler = function(state)
        local this_state = get_state()
        if state == this_state then
          state.git_status_lookup = git.status(state.git_base)
        end
      end,
    })
  end

  -- Respond to git events from git_status source or Fugitive
  if global_config.enable_git_status then
    manager.subscribe(M.name, {
      event = events.GIT_EVENT,
      handler = function()
        manager.refresh(M.name)
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
    if global_config.enable_refresh_on_write then
      manager.subscribe(M.name, {
        event = events.VIM_BUFFER_CHANGED,
        handler = function(arg)
          local afile = arg.afile or ""
          if utils.is_real_file(afile) then
            log.trace("refreshing due to vim_buffer_changed event: ", afile)
            manager.refresh("filesystem")
          else
            log.trace("Ignoring vim_buffer_changed event for non-file: ", afile)
          end
        end,
      })
    end
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

  --Configure event handlers for modified files
  if global_config.enable_modified_markers then
    manager.subscribe(M.name, {
      event = events.VIM_BUFFER_MODIFIED_SET,
      handler = wrap(manager.opened_buffers_changed),
    })
  end

  if global_config.enable_opened_markers then
    for _, event in ipairs({ events.VIM_BUFFER_ADDED, events.VIM_BUFFER_DELETED }) do
      manager.subscribe(M.name, {
        event = event,
        handler = wrap(manager.opened_buffers_changed),
      })
    end
  end

  -- Configure event handler for follow_current_file option
  if config.follow_current_file.enabled then
    manager.subscribe(M.name, {
      event = events.VIM_BUFFER_ENTER,
      handler = function(args)
        if utils.is_real_file(args.afile) then
          M.follow()
        end
      end,
    })
  end
end

---Expands or collapses the current node.
---@param state neotree.sources.filesystem.State
---@param node NuiTree.Node
---@param path_to_reveal string
---@param skip_redraw boolean?
---@param recursive boolean?
---@param callback function?
M.toggle_directory = function(state, node, path_to_reveal, skip_redraw, recursive, callback)
  local tree = state.tree
  if not node then
    node = assert(tree:get_node())
  end
  if node.type ~= "directory" then
    return
  end
  state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
  if node.loaded == false then
    local id = node:get_id()
    state.explicitly_opened_nodes[id] = true
    renderer.position.set(state, nil)
    fs_scan.get_items(state, id, path_to_reveal, callback, false, recursive)
  elseif node:has_children() then
    local updated = false
    if node:is_expanded() then
      updated = node:collapse()
      state.explicitly_opened_nodes[node:get_id()] = false
    else
      updated = node:expand()
      state.explicitly_opened_nodes[node:get_id()] = true
    end
    if updated and not skip_redraw then
      renderer.redraw(state)
    end
    if path_to_reveal then
      renderer.focus_node(state, path_to_reveal)
    end
  elseif require("neo-tree").config.filesystem.scan_mode == "deep" then
    node.empty_expanded = not node.empty_expanded
    renderer.redraw(state)
  end
end

M.prefetcher = {
  ---@param state neotree.sources.filesystem.State
  ---@param node NuiTree.Node
  prefetch = function(state, node)
    if node.type ~= "directory" then
      return
    end
    log.debug("Running fs prefetch for:" .. node:get_id())
    fs_scan.get_dir_items_async(state, node:get_id(), true)
  end,
  should_prefetch = function(node)
    return not node.loaded
  end,
}

return M
