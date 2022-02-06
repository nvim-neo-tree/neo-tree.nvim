--This file should contain all commands meant to be used by mappings.

local vim = vim
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local inputs = require("neo-tree.ui.inputs")
local popups = require("neo-tree.ui.popups")
local manager = require("neo-tree.sources.manager")

local M = {}

local refresh = utils.wrap(manager.refresh, "git_status")
local redraw = utils.wrap(manager.redraw, "git_status")

M.git_add_file = function(state)
  local node = state.tree:get_node()
  local path = node:get_id()
  local cmd = "git add " .. path
  vim.fn.system(cmd)
  refresh()
end

M.git_add_all = function(state)
  local cmd = "git add -A"
  vim.fn.system(cmd)
  refresh()
end

M.git_commit = function(state, and_push)
  local width = vim.fn.winwidth(0) - 2
  local row = vim.api.nvim_win_get_height(0) - 3
  local popup_options = {
    relative = "win",
    position = {
      row = row,
      col = 0,
    },
    size = width,
  }

  inputs.input("Commit message: ", "", function(msg)
    msg = msg:gsub('"', "'")
    local cmd = 'git commit -m "' .. msg .. '"'
    local title = "git commit"
    if and_push then
      cmd = cmd .. " && git push"
      title = "git commit && git push"
    end
    local result = vim.fn.systemlist(cmd)
    refresh()
    popups.alert(title, result)
  end, popup_options)
end

M.git_commit_and_push = function(state)
  M.git_commit(state, true)
end

M.git_push = function(state)
  inputs.confirm("Are you sure you want to push your changes?", function(yes)
    if yes then
      local result = vim.fn.systemlist("git push")
      refresh()
      popups.alert("git push", result)
    end
  end)
end

M.git_unstage_file = function(state)
  local node = state.tree:get_node()
  local path = node:get_id()
  local cmd = "git reset -- " .. path
  vim.fn.system(cmd)
  refresh()
end

M.git_revert_file = function(state)
  local node = state.tree:get_node()
  local path = node:get_id()
  local cmd = "git checkout HEAD -- " .. path
  local msg = string.format("Are you sure you want to revert %s?", node.name)
  inputs.confirm(msg, function(yes)
    if yes then
      vim.fn.system(cmd)
      refresh()
    end
  end)
end

-- ----------------------------------------------------------------------------
-- Common commands
-- ----------------------------------------------------------------------------
M.add = function(state)
  cc.add(state, refresh)
end

M.close_node = cc.close_node
M.close_window = cc.close_window

---Marks node as copied, so that it can be pasted somewhere else.
M.copy_to_clipboard = function(state)
  cc.copy_to_clipboard(state, redraw)
end

---Marks node as cut, so that it can be pasted (moved) somewhere else.
M.cut_to_clipboard = function(state)
  cc.cut_to_clipboard(state, redraw)
end

M.show_debug_info = cc.show_debug_info

---Pastes all items from the clipboard to the current directory.
M.paste_from_clipboard = function(state)
  cc.paste_from_clipboard(state, refresh)
end

M.delete = function(state)
  cc.delete(state, refresh)
end

M.open = cc.open
M.open_split = cc.open_split
M.open_vsplit = cc.open_vsplit

M.refresh = refresh

M.rename = function(state)
  cc.rename(state, refresh)
end

return M
