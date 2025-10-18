---@class neotree.clipboard.Backend
local Backend = {}

---A backend has the responsibility of storing a single instance of a clipboard for other clipboards to save.
---@return neotree.clipboard.Backend?
function Backend:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

---Given a particular state, determines whether the backend should load its saved clipboard into the state.
---Return nil if no clipboard change should be made
---@param state neotree.State
---@return neotree.clipboard.Contents? clipboard_or_nil
---@return string? err
function Backend:load(state) end

---Saves a state's clipboard to the backend.
---Returns nil when the save is not applicable.
---@param state neotree.State
---@return boolean? success_or_noop
function Backend:save(state)
  return true
end

return Backend
