local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local renderer = require("neo-tree.ui.renderer")
local log = require("neo-tree.log")

local M = {}

local clipboard_state_dir_path = vim.fn.stdpath("state") .. "/neo-tree/"
local clipboard_file_path = clipboard_state_dir_path .. "filesystem-clipboard.json"
local clipboard_file_change_triggered_by_cur_neovim_instance = false

M.save_clipboard = function(clipboard)
  local file = io.open(clipboard_file_path, "w+")
  -- We want to erase data in the file if clipboard is nil instead writing null
  if not clipboard or not file then
    return
  end

  local is_success, data = pcall(vim.json.encode, clipboard)
  if not is_success then
    log.error("Failed to save clipboard. JSON serialization error")
    return
  end
  file:write(data)
  file:flush()
  M._update_all_cilpboards(clipboard)
  clipboard_file_change_triggered_by_cur_neovim_instance = true
end

M._load_clipboard = function()
  local file = io.open(clipboard_file_path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  local is_success, clipboard = pcall(vim.json.decode, content)
  if not is_success then
    return nil
  end
  return clipboard
end

M._update_all_cilpboards = function(clipboard)
  manager._for_each_state("filesystem", function(state)
    state.clipboard = clipboard
    vim.schedule(function()
      renderer.redraw(state)
    end)
  end)
end

M.init = function()
  if vim.fn.isdirectory(clipboard_state_dir_path) == 0 then
    vim.fn.mkdir(clipboard_state_dir_path)
  end

  events.subscribe({
    event = events.STATE_CREATED,
    handler = function(state)
      if state.name ~= "filesystem" then
        return
      end
      vim.schedule(function()
        M._update_all_cilpboards(M._load_clipboard())
      end)
    end,
  })

  -- Using watch_folder because we haven't "watch_file" :)
  fs_watch.watch_folder(clipboard_state_dir_path, function()
    if not clipboard_file_change_triggered_by_cur_neovim_instance then
      M._update_all_cilpboards(M._load_clipboard())
    end
    clipboard_file_change_triggered_by_cur_neovim_instance = false
  end, true)
end

return M
