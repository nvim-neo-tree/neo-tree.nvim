local git = require("neo-tree.git")
local utils = require("neo-tree.utils")
local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local uv = vim.uv or vim.loop
local M = {}

---@param worktree_root string?
---@param git_dir string?
M.watch = function(worktree_root, git_dir)
  if not git_dir or not worktree_root then
    return
  end
  local watcher = fs_watch.watch_folder(git_dir, function(err, fname)
    if fname then
      if vim.endswith(fname, ".lock") then
        return
      end
      if fname:find("_null-ls_", 1, true) then
        -- null-ls temp file: https://github.com/jose-elias-alvarez/null-ls.nvim/pull/1075
        return
      end
    end

    if err then
      log.error("git_event_callback: ", err)
      return
    end
    utils.debounce("git_folder_exists " .. git_dir, function()
      local git_folder_stat = uv.fs_stat(git_dir)
      if git_folder_stat and git_folder_stat.type == "directory" then
        return
      end

      git.find_worktree_info(git_dir)
    end, 5000, utils.debounce_strategy.CALL_LAST_ONLY)

    vim.schedule(function()
      events.fire_event(events.GIT_EVENT)
    end)
  end)
  fs_watch.updated_watched()
  return watcher
end

return M
