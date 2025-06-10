local Backend = require("neo-tree.clipboard.sync.base")
local g = vim.g
---@class neotree.clipboard.GlobalBackend : neotree.clipboard.Backend
local GlobalBackend = Backend:new()

---@type table<string, neotree.clipboard.Contents?>
local clipboards = {}

function GlobalBackend:load(state)
  return clipboards[state.name]
end

function GlobalBackend:save(state)
  clipboards[state.name] = state.clipboard
end

return GlobalBackend
