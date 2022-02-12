local vim = vim
local events = require("neo-tree.events")
local log = require("neo-tree.log")

local M = {}

local fs_event_callback = vim.schedule_wrap(function(err, fname, status)
  if err then
    log.error("fs_event_callback: ", err)
    return
  end
  events.fire_event(events.FS_EVENT, { path = fname, status = status })
end)

local flags = {
  watch_entry = false,
  stat = false,
  recursive = false,
}

local watched = {}

M.show_watched = function()
  local items = {}
  for _, handle in pairs(watched) do
    items[handle.path] = handle.references
  end
  log.info("Watched Folders: ", vim.inspect(items))
end

---Watch a directory for changes to it's children. Not recursive.
---@param path string The directory to watch.
M.watch_folder = function(path)
  if path:find("/%.git$") or path:find("/%.git/") then
    -- git folders seem to throw off fs events constantly.
    log.debug("watch_folder(path): Skipping git folder: ", path)
    return
  end
  local h = watched[path]
  if h == nil then
    log.trace("Starting new fs watch on: ", path)
    local w = vim.loop.new_fs_event()
    watched[path] = {
      handle = w,
      path = path,
      references = 1,
    }
    w:start(path, flags, fs_event_callback)
  else
    log.trace("Incrementing references for fs watch on: ", path)
    h.references = h.references + 1
  end
end

---Stop watching a directory. If there are no more references to the handle,
---it will be destroyed. Otherwise, the reference count will be decremented.
---@param path string The directory to stop watching.
M.unwatch_folder = function(path)
  local h = watched[path]
  if h then
    log.trace("Decrementing references for fs watch on: ", path)
    h.references = h.references - 1
    if h.references < 1 then
      log.trace("No more references for fs watch on: ", path, ", stopping.")
      h.handle:stop()
      watched[path] = nil
    else
      log.trace("Still references for fs watch on: ", path, ", NOT stopping.")
    end
  else
    log.trace("(unwatch_folder) No fs watch found for: ", path)
  end
end

---Stop watching all directories. This is the nuclear option and it affects all
---sources.
M.unwatch_all = function()
  for _, h in pairs(watched) do
    h.handle:stop()
  end
  watched = {}
end

return M
