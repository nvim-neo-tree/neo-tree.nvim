---@class neotree.clipboard.Backend
local Backend = {}

---@class neotree.clipboard.Node
---@field action string
---@field node NuiTree.Node

---@alias neotree.clipboard.Contents table<string, neotree.clipboard.Node?>

---@return neotree.clipboard.Backend?
function Backend:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

---Loads the clipboard from the backend
---Return a nil clipboard to not make any changes.
---@param state neotree.State
---@return neotree.clipboard.Contents|false? clipboard
---@return string? err
function Backend:load(state) end

---Writes the clipboard to the backend
---Returns nil when nothing was saved
---@param state neotree.State
---@return boolean? success_or_noop
function Backend:save(state)
  return true
end

return Backend
