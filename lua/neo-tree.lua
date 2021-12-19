local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")

local M = {
  state = {}
}

M.setup = function (config)
  M.state.config = utils.tableMerge(defaults, config or {})
  require('neo-tree.sources.filesystem').setup(M.state.config.filesystem)
end

M.show = function (sourceName)
  sourceName = sourceName or M.state.config.defaultSource
  local source = require('neo-tree.sources.' .. sourceName)
  M.state.config.currentSource = source
  source.show(M.state)
end

return M
