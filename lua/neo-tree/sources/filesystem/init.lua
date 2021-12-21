local vim = vim
local utils = require("neo-tree.utils")
local lib = require("neo-tree.sources.filesystem.lib")

local M = {}
local myState = nil

M.loadChildren = function(id)
  lib.getItemsAsync(myState, id)
end

M.navigate = function(path)
  if path == nil then
    path = vim.fn.getcwd()
  end
  myState.path = path
  lib.getItemsAsync(myState)
  if myState.bind_to_cwd then
    vim.api.nvim_command("tcd " .. path)
  end
end

M.navigateUp = function()
  local parentPath, _ = utils.splitPath(myState.path)
  M.navigate(parentPath)
end

M.refresh = function()
  if myState.path then
    M.navigate(myState.path)
  end
end

M.setup = function(config)
  if myState == nil then
    myState = utils.tableCopy(config)
    myState.commands = require("neo-tree.sources.filesystem.commands")
    local autocmds = {}
    local refresh_cmd = ":lua require('neo-tree.sources.filesystem').refresh()"
    table.insert(autocmds, "augroup neotreefilesystem")
    table.insert(autocmds, "autocmd!")
    table.insert(autocmds, "autocmd BufWritePost * " .. refresh_cmd)
    table.insert(autocmds, "autocmd BufDelete * " .. refresh_cmd)
    if myState.bind_to_cwd then
      table.insert(autocmds, "autocmd DirChanged * :lua require('neo-tree.sources.filesystem').navigate()")
    end
    table.insert(autocmds, "augroup END")
    vim.cmd(table.concat(autocmds, "\n"))
  end
end

M.show = function()
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
