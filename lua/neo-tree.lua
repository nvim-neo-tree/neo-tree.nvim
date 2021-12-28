local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")

local M = {
  state = {}
}

M.focus = function(source_name)
  source_name = source_name or M.state.config.default_source
  local source = require('neo-tree.sources.' .. source_name)
  source.focus()
end

M.setup = function (config)
  M.state.config = utils.table_merge(defaults, config or {})
  require('neo-tree.sources.filesystem').setup(M.state.config.filesystem)
end

M.show = function (source_name)
  source_name = source_name or M.state.config.default_source
  local source = require('neo-tree.sources.' .. source_name)
  source.show()
end

return M
