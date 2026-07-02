local a = require("neo-tree.legacy.plenary.async.async")
local vararg = require("neo-tree.legacy.plenary.vararg")
-- local control = a.control
local control = require("neo-tree.legacy.plenary.async.control")
local channel = control.channel

local M = {}

M.join = function(async_fns)
  local len = #async_fns
  local results = {}
  if len == 0 then
    return results
  end

  local done = 0

  local tx, rx = channel.oneshot()

  for i, async_fn in ipairs(async_fns) do
    assert(type(async_fn) == "function", "type error :: future must be function")

    local cb = function(...)
      results[i] = { ... }
      done = done + 1
      if done == len then
        tx()
      end
    end

    a.run(async_fn, cb)
  end

  rx()

  return results
end

M.run_all = function(async_fns, callback)
  a.run(function()
    M.join(async_fns)
  end, callback)
end
function M.protected(async_fn)
  return function()
    return M.apcall(async_fn)
  end
end

---An async function that when called will yield to the neovim scheduler to be able to call the api.
M.schedule = a.wrap(vim.schedule, 1)

return M
