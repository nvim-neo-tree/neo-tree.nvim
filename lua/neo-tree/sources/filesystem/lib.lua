local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.renderer")
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

M.getItemsAsync = function(myState, parentId)
  local items = {}
  local folders = {}

  scan.scan_dir_async(parentId or myState.path, {
    hidden = myState.show_hidden or false,
    respect_gitignore = myState.respect_gitignore or false,
    search_pattern = myState.search_pattern or nil,
    add_dirs = true,
    depth = 4,
    on_insert = function(path, _type)
      local parentPath, name = utils.splitPath(path)
      local item = {
        id = path,
        name = name,
        parentPath = parentPath,
        path = path,
        type = _type,
      }
      if _type == 'directory' then
        item.children = {}
        item.loaded = false
        folders[path] = item
      else
        item.ext = item.name:match("%.(%w+)$")
      end
      local parent = folders[parentPath]
      if parent then
        parent.loaded = true
        table.insert(parent.children, item)
      else
        table.insert(items, item)
      end
    end,
    on_exit = vim.schedule_wrap(function()
      deepSort(items)
      if parentId == nil then
        local parentPath, name = utils.splitPath(myState.path)
        local root = {
          id = myState.path,
          path = parentPath,
          name = name,
          type = 'directory',
          children = items,
          loaded = true,
        }
        myState.default_expanded_nodes = { myState.path }
        renderer.showNodes({ root }, myState)
      else
        renderer.showNodes(items, myState, parentId)
      end
    end)
  })
end

return M
