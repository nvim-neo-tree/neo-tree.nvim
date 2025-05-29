local events = require("neo-tree.events")

local M = {}

---@enum (key) neotree.Clipboard.BackendNames.Builtin
local backends = {
  none = require("neo-tree.clipboard.sync.base"),
  file = require("neo-tree.clipboard.sync.file"),
  -- global = require("neo-tree.clipboard.sync.global"),
}

---@type neotree.Clipboard.Backend?
M.current_backend = nil

---@alias neotree.Config.Clipboard.Sync neotree.Clipboard.BackendNames.Builtin|neotree.Clipboard.Backend

---@param opts neotree.Config.Clipboard
M.setup = function(opts)
  opts = opts or {}
  opts.sync = opts.sync or "none"

  if type(opts.sync) == "string" then
    local selected_backend = backends[opts.sync]
    assert(selected_backend, "backend name should be valid")
    M.current_backend = selected_backend
  else
    local sync = opts.sync
    ---@cast sync -neotree.Clipboard.BackendNames.Builtin
    M.current_backend = sync
  end
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
return M
