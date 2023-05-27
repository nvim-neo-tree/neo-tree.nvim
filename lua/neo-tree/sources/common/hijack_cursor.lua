local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")

local M = {}

local setup_for_module = function(module)
  return function()
    local state = manager.get_state(module)
    local winid = state.winid
    if vim.api.nvim_get_current_win() == winid then
      local node = state.tree:get_node()
      log.debug("Cursor moved in tree window, updating cursor pos")
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1]
      local current_line = vim.api.nvim_get_current_line()
      local startIndex, _ = string.find(current_line, node.name, nil, true)
      if startIndex then
        vim.api.nvim_win_set_cursor(0, { row, startIndex - 1 })
      end
    end
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
---wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  local modules = { "filesystem", "git_status", "buffers" }
  for _, module in ipairs(modules) do
    manager.subscribe(module, {
      event = events.VIM_CURSOR_MOVED,
      handler = setup_for_module(module),
    })
  end
end

return M
