local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")

local M = {}

---@enum (key) neotree.clipboard.BackendNames.Builtin
local builtins = {
  none = require("neo-tree.clipboard.sync.base"),
  file = require("neo-tree.clipboard.sync.file"),
  global = require("neo-tree.clipboard.sync.global"),
}
vim.print(builtins)

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
  M.current_backend = assert(selected_backend:new())

  events.subscribe({
    event = events.STATE_CREATED,
    handler = function(new_state)
      local clipboard = M.current_backend:load(new_state) or {}
      if not clipboard then
        return
      end
      new_state.clipboard = clipboard
    end,
  })

  events.subscribe({
    event = events.NEO_TREE_CLIPBOARD_CHANGED,
    handler = function(state)
      local ok, err = M.current_backend:save(state)
      if ok == false then
        log.error(err)
      end

      -- try loading the changed clipboard into all other states
      manager._for_each_state(nil, function(other_state)
        if state == other_state then
          return
        end
        local modified_clipboard = M.current_backend:load(other_state)
        if not modified_clipboard then
          return
        end
        vim.print("changed clipboard of " .. ("%s%s"):format(other_state.name, other_state.id))
        other_state.clipboard = modified_clipboard
      end)
    end,
  })
end
return M
