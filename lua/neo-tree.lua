local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")

local M = {
  state = {}
}

M.setup = function (config)
  M.state.config = utils.tableMerge(defaults, config or {})
  require('neo-tree.sources.filesystem').setup(M.state.config.filesystem)
end

M.show = function (source_name)
  source_name = source_name or M.state.config.default_source
  local source = require('neo-tree.sources.' .. source_name)
  M.state.config.currentSource = source
  source.show(M.state)
end

return M
