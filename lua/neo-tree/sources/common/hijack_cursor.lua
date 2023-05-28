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

--Enables cursor hijack behavior for given sources
---@param sources table List of all sources to configure hijack for
M.setup = function(sources)
  for _, source_name in ipairs(sources) do
    manager.subscribe(source_name, {
      event = events.VIM_CURSOR_MOVED,
      handler = setup_for_module(source_name),
    })
  end
end

return M
