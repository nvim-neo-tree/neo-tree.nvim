local a = require("neo-tree.legacy.plenary.async.async")
local tbl = require("plenary.tbl")

local M = {}

M.channel = {}

---Creates a oneshot channel
---returns a sender and receiver function
---the sender is not async while the receiver is
---@return function, function
M.channel.oneshot = function()
  local val = nil
  local saved_callback = nil
  local sent = false
  local received = false
  local is_single = false

  --- sender is not async
  --- sends a value which can be nil
  local sender = function(...)
    assert(not sent, "Oneshot channel can only send once")
    sent = true

    if saved_callback ~= nil then
      saved_callback(...)
      return
    end

    -- optimise for when there is only one or zero argument, no need to pack
    local nargs = select("#", ...)
    if nargs == 1 or nargs == 0 then
      val = ...
      is_single = true
    else
      val = tbl.pack(...)
    end
  end

  --- receiver is async
  --- blocks until a value is received
  local receiver = a.wrap(function(callback)
    assert(not received, "Oneshot channel can only receive one value!")

    if sent then
      received = true
      if is_single then
        return callback(val)
      else
        return callback(tbl.unpack(val))
      end
    else
      saved_callback = callback
    end
  end, 1)

  return sender, receiver
end

return M
