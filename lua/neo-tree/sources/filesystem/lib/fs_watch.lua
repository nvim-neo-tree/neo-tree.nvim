local events = require("neo-tree.events")
local log = require("neo-tree.log")
local git = require("neo-tree.git")
local utils = require("neo-tree.utils")
local uv = vim.uv or vim.loop

local M = {}

local flags = {
  watch_entry = false,
  stat = false,
  recursive = false,
}

---@type table<string, neotree.sources.filesystem.Watcher?>
local watchers = {}

M.show_watched = function()
  local items = {}
  for p, handle in pairs(watchers) do
    items[p] = handle.references
  end
  log.info("Watched Folders: ", vim.inspect(items))
end

---@class neotree.sources.filesystem.Watcher
---@field handle uv.uv_fs_event_t?
---@field references integer
---@field active boolean
---@field callback fun(err: string?, name: string)
local Watcher = {}

---@param opts neotree.sources.filesystem.Watcher
function Watcher:new(opts)
  setmetatable(opts, self)
  self.__index = self
  return opts
end

---Idempotently start the watcher on the path
---@param path string
function Watcher:start(path)
  if not self.active then
    self.handle:start(path, flags, self.callback)
    self.active = true
  end
end

function Watcher:stop()
  if self.active then
    self.handle:stop()
    self.active = false
  end
end

---Watch a directory for changes to it's children. Not recursive.
---@param path string The directory to watch.
---@param custom_callback fun(err: string?, fname: string)? The callback to call when a change is detected.
---@param allow_git_watch boolean? Allow watching of git folders.
M.watch_folder = function(path, custom_callback, allow_git_watch)
  if not allow_git_watch then
    local unix_path = path:gsub("\\", "/")
    if unix_path:find("/.git/", 1, true) or vim.endswith(".git", "/.git") then
      -- git folders seem to throw off fs events constantly.
      log.debug("watch_folder(path): Skipping git folder:", path)
      return
    end
  end

  local w = watchers[path]
  if w then
    log.trace("Incrementing references for fs watch on:", path)
    w.references = w.references + 1
    return
  end
  log.trace("Creating new fs watch on:", path)
  local handle, err = uv.new_fs_event()
  if not handle then
    log.debug("Can't make fs event:", err)
    return
  end
  w = Watcher:new({
    handle = handle,
    references = 1,
    active = false,
    callback = custom_callback or function(err, fname)
      if fname and fname:match("^%.null[-]ls_.+") then
        -- null-ls temp file: https://github.com/jose-elias-alvarez/null-ls.nvim/pull/1075
        return
      end
      if err then
        log.error("file_event_callback: ", err)
        return
      end
      vim.schedule(function()
        events.fire_event(events.FS_EVENT, { afile = path })
      end)
    end,
  })
  log.trace("Incrementing references for fs watch on:", path)
  watchers[path] = w
end

M.updated_watched = function()
  for path, w in pairs(watchers) do
    if w.references > 0 then
      log.trace("References added for fs watch on:", path, ", starting.")
      w:start(path)
    else
      log.trace("No more references for fs watch on:", path, ", stopping.")
      w:stop()
    end
  end
end

---Stop watching a directory. If there are no more references to the handle,
---it will eventually be destroyed. Otherwise, the reference count will be decremented.
---@param path string The directory to stop watching.
M.unwatch_folder = function(path, callback_id)
  local w = watchers[path]
  if w then
    log.trace("Decrementing references for fs watch on:", path, callback_id)
    w.references = w.references - 1
  else
    log.trace("(unwatch_folder) No fs watch found for:", path)
  end
end

---Stop watching all directories. This is the nuclear option and it affects all
---sources.
M.stop_watching = function()
  for _, h in pairs(watchers) do
    h:stop()
  end
  watchers = {}
end

return M
