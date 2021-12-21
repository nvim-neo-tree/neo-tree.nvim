local vim = vim
local utils = require("neo-tree.utils")
local lib = require("neo-tree.sources.filesystem.lib")

local M = {}
local myState = nil

M.loadChildren = function(id)
  lib.getItemsAsync(myState, id)
end

M.navigate = function(path)
  myState.path = path
  lib.getItemsAsync(myState)
end

M.navigateUp = function()
  local parentPath, _ = utils.splitPath(myState.path)
  M.navigate(parentPath)
end

M.refresh = function()
  M.navigate(myState.path)
end

M.setup = function(config)
  if myState == nil then
    myState = utils.tableCopy(config)
    myState.commands = require("neo-tree.sources.filesystem.commands")
  end
end

M.show = function()
  if myState.path == nil then
    myState.path = vim.fn.getcwd()
  end
  M.navigate(myState.path)
end

M.toggle_hidden = function()
  myState.show_hidden = not myState.show_hidden
  M.show()
end

M.toggle_gitignore = function()
  myState.respect_gitignore = not myState.respect_gitignore
  M.show()
end

M.search = function(pattern)
  myState.search_pattern = pattern
  M.show()
end

return M
