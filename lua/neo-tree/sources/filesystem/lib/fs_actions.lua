-- This file is for functions that mutate the filesystem.

-- This code started out as a copy from:
-- https://github.com/mhartington/dotfiles
-- and modified to fit neo-tree's api.
-- Permalink: https://github.com/mhartington/dotfiles/blob/7560986378753e0c047d940452cb03a3b6439b11/config/nvim/lua/mh/filetree/init.lua
local vim = vim
local api = vim.api
local loop = vim.loop
local scan = require("plenary.scandir")
local utils = require("neo-tree.utils")
local inputs = require("neo-tree.ui.inputs")
local events = require("neo-tree.events")
local log = require("neo-tree.log")

local M = {}

local function clear_buffer(path)
  local buf = utils.find_buffer_by_name(path)
  if buf < 1 then
    return
  end
  local alt = vim.fn.bufnr("#")
  -- Check all windows to see if they are using the buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      -- if there is no alternate buffer yet, create a blank one now
      if alt < 1 or alt == buf then
        alt = vim.api.nvim_create_buf(true, false)
      end
      -- replace the buffer displayed in this window with the alternate buffer
      vim.api.nvim_win_set_buf(win, alt)
    end
  end
  local success, msg = pcall(vim.api.nvim_buf_delete, buf, { force = true })
  if not success then
    log.error("Could not clear buffer: ", msg)
  end
end

local function create_all_parents(path)
  local create_all_as_folders
  function create_all_as_folders(in_path)
    if not loop.fs_stat(in_path) then
      local parent, _ = utils.split_path(in_path)
      if parent then
        create_all_as_folders(parent)
      end
      loop.fs_mkdir(in_path, 493)
    end
  end

  local parent_path, _ = utils.split_path(path)
  create_all_as_folders(parent_path)
end

local get_unused_name
function get_unused_name(destination, name_chosen_callback, first_message)
  if loop.fs_stat(destination) then
    local parent_path, name = utils.split_path(destination)
    local message = first_message or name .. " already exists. Please enter a new name: "
    inputs.input(message, name, function(new_name)
      if new_name and string.len(new_name) > 0 then
        local new_path = parent_path .. utils.path_separator .. new_name
        get_unused_name(new_path, name_chosen_callback)
      end
    end)
  else
    name_chosen_callback(destination)
  end
end
-- Move Node
M.move_node = function(source, destination, callback)
  local parent_path, name = utils.split_path(source)
  get_unused_name(destination or source, function(dest)
    create_all_parents(dest)
    loop.fs_rename(source, dest, function(err)
      if err then
        log.error("Could not move the files")
        return
      end
      vim.schedule(function()
        events.fire_event(events.FILE_MOVED, {
          source = source,
          destination = dest,
        })
        if callback then
          callback(source, dest)
        end
      end)
    end)
  end, 'Move "' .. name .. '" to:')
end

-- Copy Node
M.copy_node = function(source, _destination, callback)
  local parent_path, name = utils.split_path(source)
  get_unused_name(_destination or source, function(destination)
    create_all_parents(destination)
    loop.fs_copyfile(source, destination, function(err)
      if err then
        log.error("Could not copy the files")
        return
      end
      vim.schedule(function()
        events.fire_event(events.FILE_ADDED, destination)
        if callback then
          callback(source, destination)
        end
      end)
    end)
  end, 'Copy "' .. name .. '" to:')
end

-- Create Node
M.create_node = function(in_directory, callback)
  inputs.input('Enter name for new file or directory (dirs end with a "/"):', "", function(name)
    if not name or name == "" then
      return
    end
    local destination = in_directory .. utils.path_separator .. name
    if loop.fs_stat(destination) then
      log.warn("File already exists")
      return
    end

    create_all_parents(destination)
    if vim.endswith(destination, "/") then
      loop.fs_mkdir(destination, 493)
    else
      local open_mode = loop.constants.O_CREAT + loop.constants.O_WRONLY + loop.constants.O_TRUNC
      local fd = loop.fs_open(destination, "w", open_mode)
      if not fd then
        api.nvim_err_writeln("Could not create file " .. name)
        return
      end
      loop.fs_chmod(destination, 420)
      loop.fs_close(fd)
    end

    if callback then
      vim.schedule(function()
        events.fire_event(events.FILE_ADDED, destination)
        if callback then
          callback(destination)
        end
      end)
    end
  end)
end

-- Delete Node
M.delete_node = function(path, callback)
  local parent_path, name = utils.split_path(path)
  local msg = string.format("Are you sure you want to delete '%s'?", name)

  local stat = loop.fs_stat(path)
  local _type = stat.type
  if _type == "link" then
    local link_to = loop.fs_readlink(path)
    if not link_to then
      log.error("Could not read link")
      return
    end
    _type = loop.fs_stat(link_to)
  end
  if _type == "directory" then
    local children = scan.scan_dir(path, {
      hidden = true,
      respect_gitignore = false,
      add_dirs = true,
      depth = 1,
    })
    if #children > 0 then
      msg = "WARNING: Dir not empty! " .. msg
    end
  end

  inputs.confirm(msg, function(confirmed)
    if not confirmed then
      return
    end

    local function delete_dir(dir_path)
      local handle = loop.fs_scandir(dir_path)
      if type(handle) == "string" then
        return api.nvim_err_writeln(handle)
      end

      while true do
        local child_name, t = loop.fs_scandir_next(handle)
        if not child_name then
          break
        end

        local child_path = dir_path .. "/" .. child_name
        if t == "directory" then
          local success = delete_dir(child_path)
          if not success then
            log.error("failed to delete ", child_path)
            return false
          end
        else
          local success = loop.fs_unlink(child_path)
          if not success then
            return false
          end
          clear_buffer(child_path)
        end
      end
      return loop.fs_rmdir(dir_path)
    end

    if _type == "directory" then
      local success = delete_dir(path)
      if not success then
        return api.nvim_err_writeln("Could not remove directory: " .. path)
      end
    else
      local success = loop.fs_unlink(path)
      if not success then
        return api.nvim_err_writeln("Could not remove file: " .. path)
      end
      clear_buffer(path)
    end

    vim.schedule(function()
      events.fire_event(events.FILE_DELETED, path)
      if callback then
        callback(path)
      end
    end)
  end)
end

-- Rename Node
M.rename_node = function(path, callback)
  local parent_path, name = utils.split_path(path)
  local msg = string.format('Enter new name for "%s":', name)

  inputs.input(msg, name, function(new_name)
    -- If cancelled
    if not new_name or new_name == "" then
      log.info("Operation canceled")
      return
    end

    local destination = parent_path .. utils.path_separator .. new_name
    -- If aleady exists
    if loop.fs_stat(destination) then
      log.warn(destination, " already exists")
      return
    end

    local complete = vim.schedule_wrap(function()
      events.fire_event(events.FILE_RENAMED, {
        source = path,
        destination = destination,
      })
      if callback then
        callback(path, destination)
      end
      log.info("Renamed " .. new_name .. " successfully")
    end)

    loop.fs_rename(path, destination, function(err)
      if err then
        log.warn("Could not rename the files")
        return
      else
        log.info("Renamed " .. name .. " successfully")
        complete()
      end
    end)
  end)
end

return M
