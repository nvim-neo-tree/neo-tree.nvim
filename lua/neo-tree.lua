local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")

local M = {
  config = {}
}

M.focus = function(source_name)
  source_name = source_name or M.config.default_source
  local source = require('neo-tree.sources.' .. source_name)
  source.focus()
end

M.setup = function(config)
  M.config = utils.table_merge(defaults, config or {})
  require('neo-tree.sources.filesystem').setup(M.config.filesystem)
end

M.show = function(source_name)
  source_name = source_name or M.config.default_source
  local source = require('neo-tree.sources.' .. source_name)
  source.show()
end

return M
