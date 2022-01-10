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

local M = {}

local function clear_buffer(path)
  for _, buf in pairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf) == path then
      api.nvim_command(":bwipeout! " .. buf)
    end
  end
end

local get_unused_name

function get_unused_name(destination, name_chosen_callback)
  if loop.fs_stat(destination) then
    local parent_path, name = utils.split_path(destination)
    inputs.input(name .. " already exists. Please enter a new name: ", name, function(new_name)
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
  get_unused_name(destination, function(dest)
    loop.fs_rename(source, dest, function(err)
      if err then
        print("Could not move the files")
        return
      end
      if callback then
        vim.schedule_wrap(function()
          callback(source, dest)
        end)()
      end
    end)
  end)
end

-- Copy Node
M.copy_node = function(source, _destination, callback)
  get_unused_name(_destination, function(destination)
    loop.fs_copyfile(source, destination)
    local handle
    handle = loop.spawn("cp", { args = { "-r", source, destination } }, function(code)
      handle:close()
      if code ~= 0 then
        print("copy failed")
        return
      end
      if callback then
        vim.schedule_wrap(function()
          callback(source, destination)
        end)()
      end
    end)
  end)
end

-- Create Node
M.create_node = function(in_directory, callback)
  inputs.input('Enter name for new file or directory (dirs end with a "/"):', "", function(name)
    if not name or name == "" then
      return
    end
    local destination = in_directory .. utils.path_separator .. name
    if loop.fs_stat(destination) then
      print("File already exists")
      return
    end

    if vim.endswith(destination, "/") then
      loop.fs_mkdir(destination, 493)
    else
      --create_dirs_if_needed(parent_path)
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
      vim.schedule_wrap(function()
        callback(destination)
      end)()
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
      print("Could not read link")
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
            print("failed to delete ", child_path)
            return false
          end
        else
          clear_buffer(child_path)
          local success = loop.fs_unlink(child_path)
          if not success then
            return false
          end
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

    if callback then
      vim.schedule_wrap(function()
        callback(path)
      end)()
    end
  end)
end

-- Rename Node
M.rename_node = function(path, callback)
  local parent_path, name = utils.split_path(path)
  local msg = string.format('Enter new name for "%s":', name)

  inputs.input(msg, name, function(new_name)
    -- If cancelled
    if not new_name or new_name == "" then
      print("Operation canceled")
      return
    end

    local destination = parent_path .. utils.path_separator .. new_name
    -- If aleady exists
    if loop.fs_stat(destination) then
      print(destination, " already exists")
      return
    end

    local complete = vim.schedule_wrap(function()
      if callback then
        callback(path, destination)
      end
      print("Renamed " .. new_name .. " successfully")
    end)

    loop.fs_rename(path, destination, function(err)
      if err then
        print("Could not rename the files")
        return
      else
        print("Renamed " .. name .. " successfully")
        complete()
      end
    end)
  end)
end

return M
