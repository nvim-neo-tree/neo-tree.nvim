local events = require("neo-tree.events")
local log = require("neo-tree.log")
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

---@class neotree.sources.filesystem.WatcherOpts
---@field handle uv.uv_fs_event_t?
---@field references integer
---@field active boolean
---@field callback fun(err: string?, name: string)

---@class neotree.sources.filesystem.Watcher : neotree.sources.filesystem.WatcherOpts
local Watcher = {}

---@param opts neotree.sources.filesystem.WatcherOpts
function Watcher:new(opts)
  setmetatable(opts, self)
  self.__index = self
  ---@cast opts neotree.sources.filesystem.Watcher
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
---@param callback fun(err: string?, fname: string) The callback to call when a change is detected.
---@return neotree.sources.filesystem.Watcher?
M.watch_folder = function(path, callback)
  local w = watchers[path]
  if w then
    log.trace("Incrementing references for fs watch on:", path)
    w.references = w.references + 1
    return w
  end
  log.trace("Creating new fs watch on:", path)
  local handle, err = uv.new_fs_event()
  if not handle then
    log.debug("Can't make fs event:", err)
    return nil
  end
  w = Watcher:new({
    handle = handle,
    references = 1,
    active = false,
    callback = callback,
  })
  log.trace("Incrementing references for fs watch on:", path)
  watchers[path] = w
  return w
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
