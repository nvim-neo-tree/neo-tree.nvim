local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.renderer")
local scan = require('plenary.scandir')


local M = {}
local myState = nil

local commands = {
  open = function(state)
    local tree = state.tree
    local node = tree:get_node()
    if node.type == 'directory' then
      if node.loaded == false then
        M.loadChildren(node.id)
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
    else
      vim.cmd("wincmd p")
      vim.cmd("e " .. node.id)
    end
  end,
  setRoot = function(state)
    local tree = state.tree
    local node = tree:get_node()
    if node.type == 'directory' then
      M.navigate(node.id)
    end
  end,
  toggleHidden = function(state)
    M.toggleHidden()
  end,
  toggleGitIgnore = function (state)
    M.toggleGitIgnore()
  end,
  up = function(state)
    M.navigateUp()
  end,
}

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

local function getItemsAsync(parentId)
  local items = {}
  local folders = {}

  scan.scan_dir_async(parentId or myState.path, {
    hidden = myState.showHidden or false,
    respect_gitignore = myState.respectGitIgnore or false,
    search_pattern = myState.searchPattern or nil,
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
          _is_expanded = true
        }
        myState.expanded_nodes = myState.expanded_nodes or {}
        myState.expanded_nodes[myState.path] = true
        renderer.showNodes({ root }, myState)
      else
        renderer.showNodes(items, myState, parentId)
      end
    end)
  })
end

M.loadChildren = function(id)
  getItemsAsync(id)
end

M.navigate = function(path)
  myState.path = path
  getItemsAsync()
end

M.navigateUp = function()
  local parentPath, _ = utils.splitPath(myState.path)
  M.navigate(parentPath)
end

M.setup = function(config)
  if myState == nil then
    myState = utils.tableCopy(config)
    myState.commands = commands
  end
end

M.show = function()
  if myState.path == nil then
    myState.path = vim.fn.expand("%:p:h") or vim.fn.expand('~')
  end
  M.navigate(myState.path)
end

M.toggleHidden = function()
  myState.showHidden = not myState.showHidden
  M.show()
end

M.toggleGitIgnore = function()
  myState.respectGitIgnore = not myState.respectGitIgnore
  M.show()
end

M.search = function(pattern)
  myState.searchPattern = pattern
  M.show()
end

return M
