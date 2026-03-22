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

---@param path string
---@param opts { recursive: boolean?, remove: boolean? }?
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
local function ensure_writable_dir(path)
  if dir_is_writable(path) then
    return true
  end
  if not mkdir(path, { recursive = true }) then
    return false
  end
  return dir_is_writable(path)
end
return function()
  if utils.is_windows then
    log.warn("Freedesktop trash module does not support Windows.")
    return nil
  end
  local data_home = xdg.data_home
  local trash_dir = utils.path_join(data_home, "Trash")
  local files_dir = utils.path_join(trash_dir, "files")
  local info_dir = utils.path_join(trash_dir, "info")
  local setup = ensure_writable_dir(trash_dir)
    and ensure_writable_dir(files_dir)
    and ensure_writable_dir(info_dir)
  if not setup then
    return nil
  end

  return function(paths)
    for i, path in ipairs(paths) do
      local _, filename = utils.split_path(path)

      -- 2. Create unique name in trash to avoid collisions
      local trash_filename = filename
      local counter = 0
      while uv.fs_lstat(utils.path_join(files_dir, trash_filename)) do
        counter = counter + 1
        trash_filename = filename .. "." .. counter
      end

      -- 3. Create the .trashinfo file
      -- Format requires [Trash Info] header, Path, and DeletionDate
      local info_content = string.format(
        [[
[Trash Info]
Path=%s
DeletionDate=%s"
]],
        path,
        os.date("%Y%m%dT%H:%M:%S")
      )

      local info_file_path = utils.path_join(info_dir, trash_filename .. ".trashinfo")
      local f, open_err = io.open(info_file_path, "w")
      if not f then
        return false, "Failed to create trashinfo: " .. (open_err or "")
      end
      f:write(info_content)
      f:close()

      -- 4. Move the file to the trash/files directory
      -- Using os.rename (Note: this only works on the same filesystem)
      local success, move_err = uv.fs_rename(path, utils.path_join(files_dir, trash_filename))

      if not success then
        -- Cleanup info file if move fails
        os.remove(info_file_path)
        return false, "Failed to move file to trash: " .. (move_err or "unknown error")
      end
    end

    return true
  end
end
