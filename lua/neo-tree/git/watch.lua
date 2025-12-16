local git = require("neo-tree.git")
local utils = require("neo-tree.utils")
local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local uv = vim.uv or vim.loop
local M = {}

---@param git_dir string?
local function watch_git_dir(_, git_dir)
  if not git_dir then
    return
  end
  fs_watch.watch_folder(git_dir, function(err, fname)
    if fname and fname:match("^.+%.lock$") then
      return
    end
    if fname and fname:match("^%._null-ls_.+") then
      -- null-ls temp file: https://github.com/jose-elias-alvarez/null-ls.nvim/pull/1075
      return
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
    end, 1000, utils.debounce_strategy.CALL_LAST_ONLY)

    vim.schedule(function()
      events.fire_event(events.GIT_EVENT)
    end)
  end, true)
end

---If a folder contains a .git index, watches it
---@param path string
---@param async any
M.watch = function(path, async)
  if async then
    git.find_worktree_info(path, watch_git_dir)
  else
    local _, git_dir = git.find_worktree_info(path)
    watch_git_dir(git_dir)
  end
end

---@param git_dir string?
local function unwatch_git_dir(_, git_dir)
  if not git_dir then
    return
  end
  fs_watch.unwatch_folder(git_dir)
end

---@param path string
---@param async any
M.unwatch = function(path, async)
  if async then
    git.find_worktree_info(path, unwatch_git_dir)
  else
    local _, git_dir = git.find_worktree_info(path)
    unwatch_git_dir(git_dir)
  end
end

return M
