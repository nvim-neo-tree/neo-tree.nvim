local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local renderer = require("neo-tree.ui.renderer")
local log = require("neo-tree.log")

local M = {}

local clipboard_state_dir_path = vim.fn.stdpath("state") .. "/neo-tree/"
local clipboard_file_path = clipboard_state_dir_path .. "filesystem-clipboard.json"
local clipboard_file_last_mtime = nil

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
  clipboard_file_last_mtime = vim.uv.fs_stat(clipboard_file_path).mtime
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

M._update_cilpboard = function()
  if not vim.fn.filereadable(clipboard_file_path) then
    return
  end
  local cur_mtime = vim.uv.fs_stat(clipboard_file_path).mtime
  if
    not clipboard_file_last_mtime
    -- We need exactly >= because it allows us to synchronize the clipboard
    -- even with trees openned in another window (in the current Neovim instance)
    or M._is_left_mtime_greater_or_equal(cur_mtime, clipboard_file_last_mtime)
  then
    local clipboard = M._load_clipboard()
    manager._for_each_state("filesystem", function(state)
      state.clipboard = clipboard
      vim.schedule(function()
        renderer.redraw(state)
      end)
    end)
    clipboard_file_last_mtime = cur_mtime
  end
end

M._is_left_mtime_greater_or_equal = function(a, b)
  if a.sec > b.sec then
    return true
  elseif a.sec == b.sec and a.nsec >= b.nsec then
    return true
  end
  return false
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
        M._update_cilpboard()
      end)
    end,
  })

  -- Using watch_folder because we haven't "watch_file" :)
  fs_watch.watch_folder(clipboard_state_dir_path, function()
    M._update_cilpboard()
  end, true)
end

return M
