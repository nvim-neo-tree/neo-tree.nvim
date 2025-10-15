local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")
local renderer = require("neo-tree.ui.renderer")

local M = {}

---@enum (key) neotree.clipboard.BackendNames.Builtin
local builtins = {
  none = require("neo-tree.clipboard.sync.base"),
  global = require("neo-tree.clipboard.sync.global"),
  universal = require("neo-tree.clipboard.sync.universal"),
}

---@type table<string, neotree.clipboard.Backend?>
M.backends = builtins

---@alias neotree.Config.Clipboard.Sync neotree.clipboard.BackendNames.Builtin|neotree.clipboard.Backend

---@class (exact) neotree.Config.Clipboard
---@field sync neotree.Config.Clipboard.Sync?

---@param opts neotree.Config.Clipboard
M.setup = function(opts)
  opts = opts or {}
  opts.sync = opts.sync or "none"

  ---@type neotree.clipboard.Backend?
  local selected_backend
  if type(opts.sync) == "string" then
    selected_backend = M.backends[opts.sync]
  elseif type(opts.sync) == "table" then
    local sync = opts.sync
    ---@cast sync -neotree.clipboard.BackendNames.Builtin
    selected_backend = sync
  end

  if not selected_backend then
    log.error("invalid clipboard sync method, disabling sync")
    selected_backend = builtins.none
  end
  M.current_backend = log.assert(selected_backend:new())

  events.subscribe({
    event = events.STATE_CREATED,
    ---@param new_state neotree.State
    handler = function(new_state)
      local clipboard, err = M.current_backend:load(new_state)
      if not clipboard then
        log.assert(not err, err)
        return
      end
      new_state.clipboard = clipboard
    end,
  })

  events.subscribe({
    event = events.NEO_TREE_CLIPBOARD_CHANGED,
    ---@param state neotree.State
    handler = function(state)
      local ok, err = M.current_backend:save(state)
      if ok == false then
        log.error(err)
      end
      M.sync_to_clipboards(state)
    end,
  })
end

---@param exclude_state neotree.State?
function M.sync_to_clipboards(exclude_state)
  -- try loading the changed clipboard into all other states
  vim.schedule(function()
    manager._for_each_state(nil, function(state)
      if state == exclude_state then
        return
      end
      local modified_clipboard, err = M.current_backend:load(state)
      if not modified_clipboard then
        if err then
          log.error(err)
        end
        return
      end
      state.clipboard = modified_clipboard
      renderer.redraw(state)
    end)
  end)
end

return M
