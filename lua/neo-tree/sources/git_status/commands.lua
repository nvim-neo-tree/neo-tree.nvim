--This file should contain all commands meant to be used by mappings.

local vim = vim
local cc = require("neo-tree.sources.common.commands")
local gs = require("neo-tree.sources.git_status")
local utils = require("neo-tree.utils")
local inputs = require("neo-tree.ui.inputs")
local popups = require("neo-tree.ui.popups")

local M = {}

M.git_add_file = function(state)
  local node = state.tree:get_node()
  local path = node:get_id()
  local cmd = "git add " .. path
  vim.fn.system(cmd)
  gs.refresh()
end

M.git_add_all = function(state)
  local cmd = "git add -A"
  vim.fn.system(cmd)
  gs.refresh()
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
    gs.refresh()
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
      gs.refresh()
      popups.alert("git push", result)
    end
  end)
end

M.git_unstage_file = function(state)
  local node = state.tree:get_node()
  local path = node:get_id()
  local cmd = "git reset -- " .. path
  vim.fn.system(cmd)
  gs.refresh()
end

M.git_revert_file = function(state)
  local node = state.tree:get_node()
  local path = node:get_id()
  local cmd = "git checkout HEAD -- " .. path
  local msg = string.format("Are you sure you want to revert %s?", node.name)
  inputs.confirm(msg, function(yes)
    if yes then
      vim.fn.system(cmd)
      gs.refresh()
    end
  end)
end

-- ----------------------------------------------------------------------------
-- Common commands
-- ----------------------------------------------------------------------------
M.add = function(state)
  cc.add(state, gs.refresh)
end

M.close_node = cc.close_node

---Marks node as copied, so that it can be pasted somewhere else.
M.copy_to_clipboard = function(state)
  cc.copy_to_clipboard(state, gs.redraw)
end

---Marks node as cut, so that it can be pasted (moved) somewhere else.
M.cut_to_clipboard = function(state)
  cc.cut_to_clipboard(state, gs.redraw)
end

M.show_debug_info = cc.show_debug_info

---Pastes all items from the clipboard to the current directory.
M.paste_from_clipboard = function(state)
  cc.paste_from_clipboard(state, gs.refresh)
end

M.delete = function(state)
  cc.delete(state, gs.refresh)
end

M.open = cc.open
M.open_split = cc.open_split
M.open_vsplit = cc.open_vsplit

M.refresh = gs.refresh

M.rename = function(state)
  cc.rename(state, gs.refresh)
end

return M
