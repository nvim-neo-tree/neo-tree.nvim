local vim = vim
local utils = require("neo-tree.utils")
local lib = require("neo-tree.sources.filesystem.lib")
local renderer = require("neo-tree.renderer")

local M = {}
local myState = nil

M.dir_changed = function()
  if myState.path and renderer.window_exists(myState) then
    M.navigate()
  end
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

M.navigate_up = function()
  local parentPath, _ = utils.splitPath(myState.path)
  M.navigate(parentPath)
end

M.refresh = function()
  if myState.path and renderer.window_exists(myState) then
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
      table.insert(autocmds, "autocmd DirChanged * :lua require('neo-tree.sources.filesystem').dir_changed()")
    end
    table.insert(autocmds, "augroup END")
    vim.cmd(table.concat(autocmds, "\n"))
  end
end

M.show = function()
  M.navigate(myState.path)
end

M.toggle_directory = function ()
  lib.toggle_directory(myState)
end

M.toggle_hidden = function()
  myState.show_hidden = not myState.show_hidden
  M.show()
end

M.toggle_gitignore = function()
  myState.respect_gitignore = not myState.respect_gitignore
  M.show()
end

M.search = function()
  require("neo-tree.sources.filesystem.search").show_search(myState)
end

return M
