-- This files holds code for scanning the filesystem to build the tree.
local uv = vim.loop

local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local filter_external = require("neo-tree.sources.filesystem.lib.filter_external")
local file_items = require("neo-tree.sources.common.file-items")
local log = require("neo-tree.log")
local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
local git = require("neo-tree.git")

local Path = require "plenary.path"
local os_sep = Path.path.sep

local M = {}

local on_directory_loaded = function(context, dir_path)
  local state = context.state
  local scanned_folder = context.folders[dir_path]
  if scanned_folder then
    scanned_folder.loaded = true
  end
  if state.use_libuv_file_watcher then
    local root = context.folders[dir_path]
    if root then
      if root.is_link then
        log.trace("Adding fs watcher for ", root.link_to)
        fs_watch.watch_folder(root.link_to)
      else
        log.trace("Adding fs watcher for ", root.path)
        fs_watch.watch_folder(root.path)
      end
    end
  end
end

local dir_complete = function(context, dir_path)
  local paths_to_load = context.paths_to_load
  local folders = context.folders

  on_directory_loaded(context, dir_path)

  -- check to see if there are more folders to load
  local next_path = nil
  while #paths_to_load > 0 and not next_path do
    next_path = table.remove(paths_to_load)
    -- ensure that the path is still valid
    local success, result = pcall(vim.loop.fs_stat, next_path)
    -- ensure that the result is a directory
    if success and result and result.type == "directory" then
      -- ensure that it is not already loaded
      local existing = folders[next_path]
      if existing and existing.loaded then
        next_path = nil
      end
    else
      -- if the path doesn't exist, skip it
      next_path = nil
    end
  end
  return next_path
end

-- async_scan scans all the directories in context.paths_to_load
-- and adds them as items to render in the UI.
local function async_scan(context, path)
  log.trace("async_scan: ", path)
  -- prepend the root path
  table.insert(context.paths_to_load, 1, path)

  local directories_scanned = 0

  local on_exit = vim.schedule_wrap(function()
    context.job_complete()
  end)

  -- from https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/scandir.lua
  local function read_dir(current_dir)
    local on_fs_scandir = function(err, fd)
      if err then
        log.error(current_dir, ": ", err)
      else
        while true do
          local name, typ = uv.fs_scandir_next(fd)
          if name == nil then
            break
          end
          local entry = current_dir .. os_sep .. name
          local success, _ = pcall(file_items.create_item, context, entry, typ)
          if not success then
            log.error("error creating item for ", path)
          end
        end
        on_directory_loaded(context, current_dir)
        directories_scanned = directories_scanned+1
        if directories_scanned == #context.paths_to_load then
          on_exit()
        end

        --local next_path = dir_complete(context, current_dir)
        --if next_path then
        --  local success, error = pcall(read_dir, next_path)
        --  if not success then
        --    log.error(next_path, ": ", error)
        --  end
        --else
        --  on_exit()
        --end
      end
    end

    uv.fs_scandir(current_dir, on_fs_scandir)
  end

  --local first = table.remove(context.paths_to_load)
  --local success, err = pcall(read_dir, first)
  --if not success then
  --  log.error(first, ": ", err)
  --end
  for i = 1, #context.paths_to_load do
    read_dir(context.paths_to_load[i])
  end
end

local function sync_scan(context, path_to_scan)
  log.trace("sync_scan: ", path_to_scan)
  local success, dir = pcall(vim.loop.fs_opendir, path_to_scan, nil, 1000)
  if not success then
    log.error("Error opening dir:", dir)
  end
  local success2, stats = pcall(vim.loop.fs_readdir, dir)
  if success2 and stats then
    for _, stat in ipairs(stats) do
      local path = path_to_scan .. utils.path_separator .. stat.name
      success, _ = pcall(file_items.create_item, context, path, stat.type)
      if not success then
        log.error("error creating item for ", path)
      end
    end
  end

  local next_path = dir_complete(context, path_to_scan)
  if next_path then
    sync_scan(context, next_path)
  else
    context.job_complete()
  end
end

M.get_items_sync = function(state, parent_id, path_to_reveal, callback)
  return M.get_items(state, parent_id, path_to_reveal, callback, false)
end

M.get_items_async = function(state, parent_id, path_to_reveal, callback)
  M.get_items(state, parent_id, path_to_reveal, callback, true)
end

M.get_items = function(state, parent_id, path_to_reveal, callback, async)
  if state.async_directory_scan == "always" then
    async = true
  elseif state.async_directory_scan == "never" then
    async = false
  elseif type(async) == "nil" then
    async = (state.async_directory_scan == "auto") or state.async_directory_scan
  end

  if not parent_id then
    M.stop_watchers(state)
  end
  local context = file_items.create_context(state)
  context.path_to_reveal = path_to_reveal

  -- Create root folder
  local root = file_items.create_item(context, parent_id or state.path, "directory")
  root.name = vim.fn.fnamemodify(root.path, ":~")
  root.loaded = true
  root.search_pattern = state.search_pattern
  context.folders[root.path] = root
  state.default_expanded_nodes = state.force_open_folders or { state.path }

  context.job_complete = function()
    local f = state.filtered_items or {}
    if f.hide_gitignored then
      local git_ignored = git.mark_ignored(state, context.all_items)
      if parent_id then
        vim.list_extend(state.git_ignored, git_ignored)
      else
        state.git_ignored = git_ignored
      end
    end

    file_items.deep_sort(root.children)
    if parent_id then
      -- lazy loading a child folder
      renderer.show_nodes(root.children, state, parent_id, callback)
    else
      -- full render of the tree
      renderer.show_nodes({ root }, state, nil, callback)
    end
  end

  if state.search_pattern then
    -- Use the external command because the plenary search is slow
    filter_external.find_files({
      filtered_items = state.filtered_items,
      find_command = state.find_command,
      limit = state.search_limit or 50,
      path = root.path,
      term = state.search_pattern,
      find_args = state.find_args,
      find_by_full_path_words = state.find_by_full_path_words,
      on_insert = function(err, path)
        if err then
          log.debug(err)
        else
          file_items.create_item(context, path)
        end
      end,
      on_exit = vim.schedule_wrap(context.job_complete),
    })
  else
    -- In the case of a refresh or navigating up, we need to make sure that all
    -- open folders are loaded.
    local path = parent_id or state.path
    context.paths_to_load = {}
    if parent_id == nil then
      if utils.truthy(state.force_open_folders) then
        for _, f in ipairs(state.force_open_folders) do
          table.insert(context.paths_to_load, f)
        end
      elseif state.tree then
        context.paths_to_load = renderer.get_expanded_nodes(state.tree, state.path)
      end
      -- Ensure that there are no nested files in the list of folders to load
      context.paths_to_load = vim.tbl_filter(function(p)
        local stats = vim.loop.fs_stat(p)
        return stats and stats.type == "directory"
      end, context.paths_to_load)
      if path_to_reveal then
        -- be sure to load all of the folders leading up to the path to reveal
        local path_to_reveal_parts = utils.split(path_to_reveal, utils.path_separator)
        table.remove(path_to_reveal_parts) -- remove the file name
        -- add all parent folders to the list of paths to load
        utils.reduce(path_to_reveal_parts, "", function(acc, part)
          local current_path = utils.path_join(acc, part)
          if #current_path > #path then -- within current root
            table.insert(context.paths_to_load, current_path)
            table.insert(state.default_expanded_nodes, current_path)
          end
          return current_path
        end)
        context.paths_to_load = utils.unique(context.paths_to_load)
      end
    end
    if async then
      async_scan(context, path)
    else
      sync_scan(context, path)
    end
  end
end

M.stop_watchers = function(state)
  if state.use_libuv_file_watcher and state.tree then
    -- We are loaded a new root or refreshing, unwatch any folders that were
    -- previously being watched.
    local loaded_folders = renderer.select_nodes(state.tree, function(node)
      return node.type == "directory" and node.loaded
    end)
    for _, folder in ipairs(loaded_folders) do
      log.trace("Unwatching folder ", folder.path)
      if folder.is_link then
        fs_watch.unwatch_folder(folder.link_to)
      else
        fs_watch.unwatch_folder(folder:get_id())
      end
    end
  else
    log.debug(
      "Not unwatching folders... use_libuv_file_watcher is ",
      state.use_libuv_file_watcher,
      " and state.tree is ",
      utils.truthy(state.tree)
    )
  end
end

return M
