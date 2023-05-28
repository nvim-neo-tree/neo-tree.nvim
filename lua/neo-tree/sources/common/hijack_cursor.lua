local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")

local M = {}

local create_handler_for_module = function(state)
  return function()
    local winid = state.winid
    if vim.api.nvim_get_current_win() == winid then
      local node = state.tree:get_node()
      log.debug("Cursor moved in tree window, hijacking cursor position")
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

--Enables cursor hijack behavior for all sources
M.setup = function()
  manager._for_each_state(nil, function (state)
    manager.subscribe(state.name, {
      event = events.VIM_CURSOR_MOVED,
      handler = create_handler_for_module(state),
    })
  end)
end

return M
