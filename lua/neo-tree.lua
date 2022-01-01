local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")
local components = require("neo-tree.ui.components")


local M = { }

local ensure_config = function ()
  if not M.config then
    M.setup({})
  end
end

M.focus = function(source_name)
  ensure_config()
  source_name = source_name or M.config.default_source
  local source = require('neo-tree.sources.' .. source_name)
  source.focus()
end

M.setup = function(config)
  local default_config = utils.table_merge(defaults, {
    filesystem = {
      components = components
    }
  })
  M.config = utils.table_merge(default_config, config or {})
  require('neo-tree.sources.filesystem').setup(M.config.filesystem)
end

M.show = function(source_name)
  ensure_config()
  source_name = source_name or M.config.default_source
  local source = require('neo-tree.sources.' .. source_name)
  source.show()
end

return M
