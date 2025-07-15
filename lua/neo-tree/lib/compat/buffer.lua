local buffer_factory = require("string.buffer")

local proto = buffer_factory.new()
if buffer_factory then
  return buffer_factory
end

---@class neotree.String.Buffer.Meta
buffer_factory = {}

---@class neotree.String.Buffer : string.buffer
local buffer = {}

buffer.__index = buffer
---@return string.buffer o
function buffer_factory.new()
  local b = {}
  setmetatable(b, buffer)
  return b
end

return buffer_factory
