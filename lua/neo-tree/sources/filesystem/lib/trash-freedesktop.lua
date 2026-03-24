-- https://specifications.freedesktop.org/trash/latest/
local uv = vim.uv
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local xdg = require("neo-tree.utils.xdg")
---@param path string
---@return boolean
local function dir_is_writable(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" and uv.fs_access(path, "w") or false
end

---@param path string @param opts { recursive: boolean?, remove: boolean? }?
---@param mode number?
---@return boolean success
---@return string? err
local function mkdir(path, opts, mode)
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
      mkdir(parent_path, opts, mode)
    else
      return false, "parent dir of " .. path .. " does not exist"
    end
  end
  local res, err = uv.fs_mkdir(path, mode or tonumber("755", 8))
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

  -- 1. Load directorysizes file into memory
  -- Format: "size mtime directory-name"
  local hash = {}
  local f = io.open(cache_file_path, "r")
  if f then
    for line in f:lines() do
      local size, mtime, name = line:match("(%d+) (%d+) (.+)")
      if size and mtime and name then
        hash[name] = {
          size = tonumber(size),
          mtime = tonumber(mtime),
          seen = false,
        }
      end
    end
    f:close()
  end

  local total_size = 0

  -- 2. List "files" directory and update sizes
  local fd = assert(uv.fs_scandir(files_dir))
  while true do
    local name, nodetype = uv.fs_scandir_next(fd)
    if not name then
      break
    end

    local item_path = files_dir .. "/" .. name

    if nodetype == "directory" then
      -- Per spec: stat the .trashinfo file in the info/ directory for mtime
      local info_path = info_dir .. "/" .. name .. ".trashinfo"
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

  -- 3. Write out hash back to temporary directorysizes file
  local out = io.open(tmp_cache_path, "w")
  if out then
    for name, data in pairs(hash) do
      if data.seen then
        out:write(string.format("%d %d %s\n", data.size, data.mtime, name))
      end
    end
    out:close()

    -- 4. Atomic rename into place
    local success, err = uv.fs_rename(tmp_cache_path, cache_file_path)
    if not success then
      return nil, "Failed to update cache file: " .. (err or "unknown error")
    end
  end

  return total_size
end

return function(paths)
  if utils.is_windows then
    log.warn("Freedesktop trash module does not support Windows.")
    return nil
  end
  local trash_dir = utils.path_join(xdg.data_home, "Trash")
  local trash_files_dir = utils.path_join(trash_dir, "files")
  local trash_info_dir = utils.path_join(trash_dir, "info")
  local setup = ensure_writable_dir(trash_dir)
    and ensure_writable_dir(trash_files_dir)
    and ensure_writable_dir(trash_info_dir)
  if not setup then
    return nil
  end
  -- Roughly check that all of these are on the same device.
  -- This rough check should be fine because if one of the paths contains a mountpoint then the move will fail anyways.
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

  for i, path in ipairs(paths) do
    if trash_dir_dev ~= get_dev(path) then
      log.at.warn.format(
        "%s and %s are not located on the same device. Skipping freedesktop trash method.",
        trash_dir,
        path
      )
      return nil
    end
  end

  return function()
    for i, path in ipairs(paths) do
      local _, filename = utils.split_path(path)

      local trash_filename = filename
      local counter = 0

      while uv.fs_lstat(utils.path_join(trash_files_dir, trash_filename)) do
        counter = counter + 1
        trash_filename = filename .. "." .. counter
      end

      local info_content = string.format(
        [[
[Trash Info]
Path=%s
DeletionDate=%s"
]],
        path,
        os.date("%Y%m%dT%H:%M:%S")
      )

      local info_file_path = utils.path_join(trash_info_dir, trash_filename .. ".trashinfo")
      local f, open_err = io.open(info_file_path, "w")
      if not f then
        return false, "Failed to create trashinfo: " .. (open_err or "")
      end
      f:write(info_content)
      f:close()

      -- Move the file to the trash/files directory
      local renamed, move_err = uv.fs_rename(path, utils.path_join(trash_files_dir, trash_filename))

      if not renamed then
        os.remove(info_file_path)
        return false, "Failed to move file to trash: " .. (move_err or "unknown error")
      end
    end
    update_trash_size_cache(trash_dir, trash_files_dir, trash_info_dir)

    return true
  end
end
