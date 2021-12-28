-- This files holds code for scanning the filesystem to build the tree.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local scan = require('plenary.scandir')

local M = {}

local function sort_items(a, b)
  if a.type == b.type then
    return a.path < b.path
  else
    return a.type < b.type
  end
end

local function deep_sort(tbl)
  table.sort(tbl, sort_items)
  for _, item in pairs(tbl) do
    if item.type == 'directory' then
      deep_sort(item.children)
    end
  end
end

local function create_item(path, _type)
  local parent_path, name = utils.split_path(path)
  local item = {
    id = path,
    name = name,
    parent_path = parent_path,
    path = path,
    type = _type,
  }
  if item.type == 'link' then
    item.is_link = true
    item.link_to = vim.loop.fs_realpath(path)
    if item.link_to ~= nil then
        item.type = vim.loop.fs_stat(item.link_to).type
    end
  end
  if item.type == 'directory' then
    item.children = {}
    item.loaded = false
  end
  return item
end

M.get_items_async = function(state, parent_id, is_lazy_load, callback)
  local depth = state.depth or 1
  local folders = {}

  -- Create root folder
  local root = create_item(parent_id or state.path, 'directory')
  root.name = vim.fn.fnamemodify(root.path, ':~')
  root.loaded = true
  folders[root.path] = root
  if state.search_pattern then
    root.search_pattern = state.search_pattern
    depth = state.search_depth or nil
  end
  state.default_expanded_nodes = { state.path }

  -- In the case of a refresh or navigating up, we need to make sure that all
  -- open folders are loaded.
  local paths_to_load = {}
  if depth and parent_id == nil and state.tree then
    paths_to_load = renderer.get_expanded_nodes(state.tree)
  end

  -- function to set (or create) parent folder
  local existing_items = {}
  local function set_parents(item)
    -- we can get duplicate items if we navigate up with open folders
    -- this is probably hacky, but it works
    if existing_items[item.id] then
      return
    end
    if not item.parent_path then
      return
    end
    local parent = folders[item.parent_path]
    if parent == nil then
      parent = create_item(item.parent_path, 'directory')
      folders[parent.id] = parent
      if state.search_pattern then
        table.insert(state.default_expanded_nodes, parent.id)
      end
      set_parents(parent)
    end
    table.insert(parent.children, item)
    existing_items[item.id] = true
  end

  -- this is the actual work of collecting items
  local function do_scan(path_to_scan)
    scan.scan_dir_async(path_to_scan, {
      hidden = state.show_hidden or false,
      respect_gitignore = state.respect_gitignore or false,
      search_pattern = state.search_pattern or nil,
      add_dirs = true,
      depth = depth,
      on_insert = function(path, _type)
        local item = create_item(path, _type)
        if _type == 'directory' then
          folders[path] = item
        else
          item.ext = item.name:match("%.(%w+)$")
        end
        set_parents(item)
      end,
      on_exit = vim.schedule_wrap(function()
        local scanned_folder = folders[path_to_scan]
        if scanned_folder then
          scanned_folder.loaded = true
        end
        -- check to see if there are more folders to load
        local next_path = nil
        while #paths_to_load > 0 and not next_path do
          next_path = table.remove(paths_to_load)
          -- ensure that the path is still valid
          local success, result = pcall(vim.loop.fs_stat, next_path)
          if success and result then
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

        if next_path then
          do_scan(next_path)
        else
            -- if there are no more folders to load, then we can sort the items
          deep_sort(root.children)
          if is_lazy_load then
            -- lazy loading a child folder
            renderer.show_nodes(root.children, state, parent_id)
          else
            -- full render of the tree
            state.before_render(state)
            renderer.show_nodes({ root }, state)
          end
          if callback then
            callback()
          end
        end
      end)
    })
  end
  do_scan(parent_id or state.path)
end

return M
