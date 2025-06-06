---@class neotree.clipboard.Backend
local Backend = {}

---@class neotree.clipboard.Contents
---@field [string] NuiTree.Node

---@return neotree.clipboard.Backend?
function Backend:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

---Loads the clipboard from the backend
---Return a nil clipboard to not make any changes.
---@param state table
---@return neotree.clipboard.Contents? clipboard
---@return string? err
function Backend:load(state)
  vim.print("base load")
  return nil, nil
end

---Writes the clipboard to the backend
---@param state table
function Backend:save(state)
  vim.print("base save")
  return true
end

return Backend
