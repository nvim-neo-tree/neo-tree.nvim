local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.renderer")
local scan = require('plenary.scandir')


local M = {}
local myState = nil

local function getItemsAsync(callback)
  local items = {}
  local folders = {}

  scan.scan_dir_async(myState.path or '~/', {
    hidden = myState.showHidden or false,
    respect_gitignore = myState.respectGitIgnore or false,
    search_pattern = myState.searchPattern or nil,
    add_dirs = true,
    depth = 4,
    on_insert = function(path, _type)
      local parts = utils.split(path, utils.pathSeparator)
      local name = table.remove(parts)
      local parentPath = table.concat(parts, utils.pathSeparator)
      if utils.pathSeparator == '/' then
        parentPath = '/' .. parentPath
      end
      local item = {
        id = path,
        name = name,
        parentPath = parentPath,
        path = path,
        type = _type,
      }
      if _type == 'directory' then
        item.children = {}
        folders[path] = item
      end
      local parent = folders[parentPath]
      if parent then
        table.insert(parent.children, item)
      else
        table.insert(items, item)
      end
    end,
    on_exit = vim.schedule_wrap(function()
      print(vim.inspect(items))
      callback(items, myState)
    end)
  })
end

M.show = function(state)
  if myState == nil then
    myState = utils.tableCopy(state.config.fileSource)
  end
  myState.path = vim.fn.expand("%:p:h") or '~/'
  getItemsAsync(renderer.showNodes)
end

return M
