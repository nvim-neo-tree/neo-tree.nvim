-- https://specifications.freedesktop.org/trash/latest/
local uv = vim.uv
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local xdg = require("neo-tree.utils.xdg")

local M = {}
---@param path string
---@return boolean
local function dir_is_writable(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" and uv.fs_access(path, "w") or false
end

---@param path string
---@param opts { recursive: boolean?, remove: boolean?, mode: number? }?
---@return boolean success
---@return string? err
local function mkdir(path, opts)
  opts = opts or {}
  local stat = uv.fs_stat(path)
  if stat then
    if stat.type ~= "directory" then
      return false, path .. " exists and is not a directory"
    end
    return true
  end
  local parent_path = utils.split_path(path)
  if not parent_path then
    return false, "could not determine parent of " .. path
  end
  local parent_stat = uv.fs_stat(parent_path)
  if not parent_stat then
    if opts.recursive then
      mkdir(parent_path, opts)
    else
      return false, "parent dir of " .. path .. " does not exist"
    end
  end
  local res, err = uv.fs_mkdir(path, opts.mode or tonumber("755", 8))
  res = res or false
  return res, err
end

---@param path string
---@return boolean is_writeable_dir
local function ensure_writable_dir(path)
  if dir_is_writable(path) then
    return true
  end
  if not mkdir(path, { recursive = true }) then
    return false
  end
  return dir_is_writable(path)
end

---@param path string
---@return number? dev
local function get_dev(path)
  local stat = uv.fs_lstat(path)
  return stat and stat.dev
end

---Implementation of the suggested algorithm for calculating the size of a trash directory.
---@param path string
---@return integer size
local function calc_dir_size(path)
  local size = 0
  local req = uv.fs_scandir(path)
  if not req then
    return 0
  end

  while true do
    local name, type = uv.fs_scandir_next(req)
    if not name then
      break
    end
    local child_path = path .. "/" .. name
    if type == "directory" then
      size = size + calc_dir_size(child_path)
    else
      local stat = uv.fs_lstat(child_path)
      size = size + (stat and stat.size or 0)
    end
  end
  return size
end

---@param trash_dir string
---@param files_dir string
---@param info_dir string
local function update_trash_size_cache(trash_dir, files_dir, info_dir)
  local tmp_cache_path = os.tmpname() .. ".directorysizes.tmp"
  local cache_file_path = utils.path_join(trash_dir, "directorysizes")

  local hash = {}
  local f = io.open(cache_file_path, "r")
  if f then
    for line in f:lines() do
      local size, mtime, name = line:match("(%d+) (%d+) (.+)")
      if size and mtime and name then
        hash[vim.uri_decode(name, "rfc2396")] = {
          size = tonumber(size),
          mtime = tonumber(mtime),
          seen = false,
        }
      end
    end
    f:close()
  end

  local total_size = 0

  for name, nodetype in vim.fs.dir(files_dir, { depth = 1 }) do
    if not name then
      break
    end

    local item_path = utils.path_join(files_dir, name)

    if nodetype == "directory" then
      local info_path = utils.path_join(info_dir, name .. ".trashinfo")
      local istat = uv.fs_stat(info_path)

      if istat then
        local mtime = istat.mtime.sec
        local entry = hash[name]

        if not entry or entry.mtime ~= mtime then
          -- Cache miss or directory modified: recalculate
          local calculated_size = calc_dir_size(item_path)
          total_size = total_size + calculated_size
          hash[name] = { size = calculated_size, mtime = mtime, seen = true }
        else
          -- Cache hit: use stored size
          total_size = total_size + entry.size
          entry.seen = true
        end
      end
    else
      local stat = uv.fs_lstat(item_path)
      if stat then
        total_size = total_size + stat.size
      end
    end
  end

  local out = io.open(tmp_cache_path, "w")
  if not out then
    return nil, "Could not update directorysizes file"
  end
  for name, data in pairs(hash) do
    if data.seen then
      out:write(string.format("%d %d %s\n", data.size, data.mtime, name))
    end
  end
  out:close()

  local success, err = uv.fs_rename(tmp_cache_path, cache_file_path)
  if not success then
    return nil, "Failed to update cache file: " .. (err or "unknown error")
  end

  return total_size
end

---@param trashed_filepath string
---@param trash_info_dir string
---@return string? restored_to
---@return string? err
local function restore(trashed_filepath, trash_info_dir)
  local _, filename = utils.split_path(trashed_filepath)
  local info_file_path = utils.path_join(trash_info_dir, filename .. ".trashinfo")

  if not uv.fs_lstat(info_file_path) then
    return nil,
      "XDG trashinfo doesn't exist at " .. info_file_path .. ", cannot determine original path"
  end

  local original_path
  for line in io.lines(info_file_path) do
    local encoded_path = line:match("^Path=([^\n]+)")
    if encoded_path then
      original_path = vim.uri_decode(encoded_path, "rfc2396")
      break
    end
  end
  if not original_path then
    return nil, ("Cannot determine original path of `%s`"):format(trashed_filepath)
  end
  if uv.fs_lstat(original_path) then
    local prompt = ("File exists at `%s`'s original path. Overwrite it with the old file from the trash?"):format(
      trashed_filepath
    )
    local choices = {
      "&Yes",
      "&No (default)",
    }
    local confirm_code = 0
    while confirm_code == 0 do
      confirm_code = vim.fn.confirm(prompt, table.concat(choices, "\n"), 2, "Warning")
    end
    if confirm_code == 1 then
    elseif confirm_code == 2 then
      return nil
    end
  end
  -- Move the file to the trash/files directory
  local renamed, move_err = uv.fs_rename(trashed_filepath, original_path)

  if not renamed then
    return nil,
      "Failed to restore " .. trashed_filepath .. " from trash: " .. (move_err or "unknown error")
  end

  os.remove(info_file_path)
  return original_path
end

---@return string trash_dir
---@return string trash_files_dir
---@return string trash_info_dir
M.calculate_trash_paths = function()
  local trash_dir = utils.path_join(xdg.data_home, "Trash")
  return trash_dir, utils.path_join(trash_dir, "files"), utils.path_join(trash_dir, "info")
end

---@type neotree.trash.RestoreFunctionGenerator
M.generate_restorer = function(paths)
  local trash_dir, trash_files_dir, trash_info_dir = M.calculate_trash_paths()
  local setup = ensure_writable_dir(trash_dir)
    and ensure_writable_dir(trash_files_dir)
    and ensure_writable_dir(trash_info_dir)

  if not setup then
    return nil
  end
  return function()
    local restored = {}
    for _, filepath in ipairs(paths) do
      local restored_filepath, err = restore(filepath, trash_info_dir)
      if restored_filepath then
        restored[#restored + 1] = restored_filepath
      elseif err then
        log.warn(err)
      end
    end

    if #restored == #paths then
      if #restored == 1 then
        log.at.info.format("Restored %s from trash", restored[1])
      else
        log.at.info.format("Restored %s files from trash", #paths)
      end
    elseif #restored < #paths then
      log.at.info.format("Restored %s/%s files from trash", #restored, #paths)
    end
    return #restored == #paths
  end
end

---@type neotree.trash.FunctionGenerator
M.generate_trashfunc = function(paths)
  if utils.is_windows then
    log.warn("Freedesktop trash module does not support Windows.")
    return nil
  end
  local trash_dir, trash_files_dir, trash_info_dir = M.calculate_trash_paths()
  local setup = ensure_writable_dir(trash_dir)
    and ensure_writable_dir(trash_files_dir)
    and ensure_writable_dir(trash_info_dir)

  if not setup then
    return nil
  end

  if vim.fn.has("nvim-0.10") == 0 then
    -- Requires neovim 0.10 for vim.uri module
    return nil
  end
  -- Roughly check that all of these are on the same device.
  -- This check should be fine because if one of the paths contains a mountpoint then the move will fail anyways.
  local trash_dir_dev = get_dev(trash_dir)
  if get_dev(trash_files_dir) ~= trash_dir_dev or get_dev(trash_info_dir) ~= trash_dir_dev then
    log.at.warn.format(
      "%s, %s, and %s are not located on the same device. Skipping freedesktop trash method.",
      trash_dir,
      trash_files_dir,
      trash_info_dir
    )
    return nil
  end

  for _, path in ipairs(paths) do
    if trash_dir_dev ~= get_dev(path) then
      log.at.warn.format(
        "%s and %s are not located on the same device. Skipping freedesktop trash method.",
        trash_dir,
        path
      )
      return nil
    end
  end

  ---@type neotree.trash._Function
  return function()
    local all_trashed = true
    local trashed_filepaths = {}
    ---@param path string
    ---@return boolean success
    ---@return string? err
    local trash_file = function(path)
      local _, filename = utils.split_path(path)
      assert(filename, "Could not determine filename for " .. path)

      local counter = 0
      -- Resolve pathname
      local trash_filename = filename
      local filename_root = vim.fn.fnamemodify(filename, ":t:r")
      local filename_extension = vim.fn.fnamemodify(filename, ":e")
      while uv.fs_lstat(utils.path_join(trash_files_dir, trash_filename)) do
        counter = counter + 1
        trash_filename = ("%s[%s].%s"):format(filename_root, counter, filename_extension)
      end

      local info_file_path = utils.path_join(trash_info_dir, trash_filename .. ".trashinfo")
      local f, open_err = io.open(info_file_path, "w")
      if not f then
        return false, "Failed to create trashinfo: " .. (open_err or "")
      end
      f:write(([[
[Trash Info]
Path=%s
DeletionDate=%s"
]]):format(vim.uri_encode(path, "rfc2396"), os.date("%Y%m%dT%H:%M:%S")))
      f:close()

      -- Move the file to the trash/files directory
      local trashed_filepath = utils.path_join(trash_files_dir, trash_filename)
      local renamed, move_err = uv.fs_rename(path, trashed_filepath)

      if not renamed then
        os.remove(info_file_path)
        return false, "Failed to move " .. path .. " to trash: " .. (move_err or "unknown error")
      end

      trashed_filepaths[#trashed_filepaths + 1] = trashed_filepath
      return true
    end

    for _, path in ipairs(paths) do
      local file_trashed, err = trash_file(path)
      if err then
        log.error(err)
      end
      all_trashed = all_trashed and file_trashed
    end
    -- local cache_updated, err = update_trash_size_cache(trash_dir, trash_files_dir, trash_info_dir)
    -- if not cache_updated then
    --   log.error(err)
    -- end
    return all_trashed, M.generate_restorer(trashed_filepaths)
  end
end

return M
