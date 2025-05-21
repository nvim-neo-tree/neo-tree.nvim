---@class neotree.Clipboard.Backend
local Backend = { balance = 0 }

---@class neotree.Clipboard.Contents
---@field [string] NuiTree.Node

---@return neotree.Clipboard.Backend?
function Backend:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

---Loads the clipboard to the backend
---@return neotree.Clipboard.Contents? valid_clipboard_or_nil
function Backend:load(v)
  return nil
end

---Writes the clipboard to the backend
---@param clipboard neotree.Clipboard.Contents?
function Backend:save(clipboard) end

return Backend
