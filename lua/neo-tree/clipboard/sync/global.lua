local Backend = require("neo-tree.clipboard.sync.base")
---@class neotree.clipboard.GlobalBackend : neotree.clipboard.Backend
local GlobalBackend = Backend:new()

---@type table<string, neotree.clipboard.Contents?>

---@class neotree.clipboard.GlobalBackend
---@field clipboards table<string>
function GlobalBackend:new()
  local backend = {}
  setmetatable(backend, self)
  self.__index = self

  ---@cast backend neotree.clipboard.GlobalBackend
  backend.clipboards = {}
  return backend
end

function GlobalBackend:save(state)
  self.clipboards[state.name] = state.clipboard
end

function GlobalBackend:load(state)
  return self.clipboards[state.name]
end

return GlobalBackend
