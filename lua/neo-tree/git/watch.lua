local git = require("neo-tree.git")
local utils = require("neo-tree.utils")
local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local uv = vim.uv or vim.loop
local M = {}

---@param git_dir string?
local function watch_git_dir(git_dir)
  if git_dir then
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
      end, 1000, utils.debounce_strategy.CALL_LAST_ONLY)
      vim.schedule(function()
        events.fire_event(events.GIT_EVENT)
      end)
    end, true)
  end
end

---If a folder contains a .git index, watches it
---@param path string
---@param async any
M.watch = function(path, async)
  if async then
    git.get_git_dir(path, watch_git_dir)
  else
    watch_git_dir(git.get_git_dir(path))
  end
end

---@param git_folder string?
local function unwatch_git_dir(git_folder)
  if git_folder then
    fs_watch.unwatch_folder(git_folder)
  end
end

---@param path string
---@param async any
M.unwatch = function(path, async)
  if async then
    git.get_git_dir(path, unwatch_git_dir)
  else
    unwatch_git_dir(git.get_git_dir(path))
  end
end

return M
