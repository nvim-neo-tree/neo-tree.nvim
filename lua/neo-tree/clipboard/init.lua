local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")
local renderer = require("neo-tree.ui.renderer")

local M = {}

---@class neotree.clipboard.Node
---@field action string
---@field node NuiTree.Node

---@alias neotree.clipboard.Contents table<string, neotree.clipboard.Node?>

---@alias neotree.clipboard.BackendNames.Builtin
---|"none"
---|"global"
---|"universal"

---@type table<string, fun():neotree.clipboard.Backend>
local builtins = {
  none = function()
    return require("neo-tree.clipboard.sync.base")
  end,
  global = function()
    return require("neo-tree.clipboard.sync.global")
  end,
  universal = function()
    return require("neo-tree.clipboard.sync.universal")
  end,
}

M.builtin_backends = builtins

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
    local lazy_loaded_backend = M.builtin_backends[opts.sync]
    if lazy_loaded_backend then
      ---@cast lazy_loaded_backend fun():neotree.clipboard.Backend
      selected_backend = lazy_loaded_backend()
    end
  elseif type(opts.sync) == "table" then
    local sync = opts.sync
    ---@cast sync -neotree.clipboard.BackendNames.Builtin
    selected_backend = sync
  end

  if not selected_backend then
    log.error("invalid clipboard sync method, disabling sync")
    selected_backend = builtins.none()
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
    handler = function(args)
      local state = args.state
      ---@cast state neotree.State
      local ok, err = M.current_backend:save(state)
      if ok == false then
        log.error(err)
      end
      if ok then
        M.update_states(state)
      end
    end,
  })
end

---Load saved clipboards into all states (except one, if provided).
---@param exclude_state neotree.State?
function M.update_states(exclude_state)
  -- try loading the changed clipboard into all other states
  vim.schedule(function()
    manager._for_each_state(nil, function(state)
      if state == exclude_state then
        return
      end
      local modified_clipboard, err = M.current_backend:load(state)
      if not modified_clipboard then
        log.assert(not err, err)
        return
      end
      state.clipboard = modified_clipboard
      renderer.redraw(state)
    end)
  end)
end

return M
