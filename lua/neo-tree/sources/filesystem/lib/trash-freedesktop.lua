-- https://specifications.freedesktop.org/trash/latest/
local uv = vim.uv
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local xdg = require("neo-tree.utils.xdg")
---@param path string
---@return boolean
local ensure_writeable_dir = function(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" and uv.fs_access(path, "w") or false
end
return function(paths)
  if utils.is_windows then
    log.warn("Freedesktop trash module does not support Windows.")
    return nil
  end
  local data_home = xdg.data_home
  local trash_dir = utils.path_join(data_home, "Trash")
  local files_dir = utils.path_join(trash_dir, "files")
  local info_dir = utils.path_join(trash_dir, "info")
  ensure_writeable_dir(trash_dir)
  ensure_writeable_dir(files_dir)
  ensure_writeable_dir(info_dir)

  return function()
    for i, path in ipairs(paths) do
      local _, filename = utils.split_path(path)
      local timestamp = os.date("%Y%m%dT%H:%M:%S")

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
        timestamp
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
      local success, move_err = os.rename(path, files_dir .. "/" .. trash_filename)

      if not success then
        -- Cleanup info file if move fails
        os.remove(info_file_path)
        return false, "Failed to move file to trash: " .. (move_err or "unknown error")
      end
    end

    return true
  end
end
