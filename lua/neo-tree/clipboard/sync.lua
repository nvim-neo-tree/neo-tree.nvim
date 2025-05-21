local events = require("neo-tree.events")

local M = {}

---@enum (key) neotree.Clipboard.BackendName
local backends = {
  none = require("neo-tree.clipboard.backends.base"),
  file = require("neo-tree.clipboard.backends.file"),
}

---@type neotree.Clipboard.Backend?
M.current_backend = nil

---@class neotree.Clipboard.Sync.Opts
---@field backend neotree.Clipboard.BackendName

---@param opts neotree.Clipboard.Sync.Opts
M.setup = function(opts)
  opts = opts or {}
  opts.backend = opts.backend or "none"

  M.current_backend = backends[opts.backend] or opts.backend
  events.subscribe({
    event = events.STATE_CREATED,
    handler = function(state)
      if state.name ~= "filesystem" then
        return
      end
      state.clipboard = M.current_backend:load()
    end,
  })

  events.subscribe({
    event = events.NEO_TREE_CLIPBOARD_CHANGED,
    handler = function(state)
      if state.name ~= "filesystem" then
        return
      end
      M.current_backend:save(state.clipboard)
    end,
  })
end
