---@brief [[
--- NOTE: This API is still under construction.
---         It may change in the future :)
---@brief ]]

local lookups = {
  uv = "neo-tree.legacy.plenary.async.uv_async",
  util = "neo-tree.legacy.plenary.async.util",
  lsp = "neo-tree.legacy.plenary.async.lsp",
  api = "neo-tree.legacy.plenary.async.api",
  control = "neo-tree.legacy.plenary.async.control",
}

local exports = setmetatable(require("neo-tree.legacy.plenary.async.async"), {
  __index = function(t, k)
    local require_path = lookups[k]
    if not require_path then
      return
    end

    local mod = require(require_path)
    t[k] = mod

    return mod
  end,
})

return exports
