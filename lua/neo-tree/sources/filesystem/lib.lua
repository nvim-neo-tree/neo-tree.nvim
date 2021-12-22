local vim = vim
local utils = require("neo-tree.utils")
local scan = require('plenary.scandir')

local M = {}

local function sortItems(a, b)
  if a.type == b.type then
    return a.path < b.path
  else
    return a.type < b.type
  end
end

local function deepSort(tbl)
  table.sort(tbl, sortItems)
  for _, item in pairs(tbl) do
    if item.type == 'directory' then
      deepSort(item.children)
    end
  end
end

local function createItem(path, _type)
  local parentPath, name = utils.splitPath(path)
  local item = {
    id = path,
    name = name,
    parentPath = parentPath,
    path = path,
    type = _type,
  }
  if item.type == 'directory' then
    item.children = {}
    item.loaded = false
  end
  return item
end

M.toggle_directory = function (myState)
  local tree = myState.tree
  local node = tree:get_node()
  if node.type ~= 'directory' then
    return
  end
  if node.loaded == false then
    M.getItemsAsync(myState, node.id)
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

M.getItemsAsync = function(myState, parentId)
  local depth = myState.depth or 4
  local folders = {}

  -- Create root folder
  local root = createItem(parentId or myState.path, 'directory')
  root.loaded = true
  folders[root.path] = root
  if myState.search_pattern then
    root.name = 'Search: ' .. myState.search_pattern .. " in " .. root.name
    depth = myState.search_depth or nil
  end
  myState.default_expanded_nodes = { myState.path }

  -- function to set (or create) parent folder
  local function set_parents(item)
    if not item.parentPath then
      return
    end
    local parent = folders[item.parentPath]
    if parent == nil then
      parent = createItem(item.parentPath, 'directory')
      folders[parent.id] = parent
      if myState.search_pattern then
        table.insert(myState.default_expanded_nodes, parent.id)
      end
      set_parents(parent)
    end
    table.insert(parent.children, item)
    parent.loaded = true
  end

  -- this is the actual work of collecting items
  scan.scan_dir_async(root.path, {
    hidden = myState.show_hidden or false,
    respect_gitignore = myState.respect_gitignore or false,
    search_pattern = myState.search_pattern or nil,
    add_dirs = true,
    depth = depth,
    on_insert = function(path, _type)
      local item = createItem(path, _type)
      if _type == 'directory' then
        folders[path] = item
      else
        item.ext = item.name:match("%.(%w+)$")
      end
      set_parents(item)
    end,
    on_exit = vim.schedule_wrap(function()
      local renderer = require("neo-tree.renderer")
      deepSort(root.children)
      if parentId == nil then
        -- full render of the tree
        myState.before_render(myState)
        renderer.showNodes({ root }, myState)
      else
        -- lazy loading a child folder
        renderer.showNodes(root.children, myState, parentId)
      end
    end)
  })
end

return M
