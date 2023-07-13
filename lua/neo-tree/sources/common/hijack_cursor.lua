local events = require("neo-tree.events")
local log = require("neo-tree.log")

local M = {}

local hijack_cursor_handler = function()
    if vim.o.filetype ~= "neo-tree" then
        return
    end
    local source = vim.api.nvim_buf_get_var(0, "neo_tree_source")
    local state = require("neo-tree.sources.manager").get_state(source)
    if state == nil then
      return
    end
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

--Enables cursor hijack behavior for all sources
M.setup = function()
  events.subscribe({
    event = events.VIM_CURSOR_MOVED,
    handler = hijack_cursor_handler,
    id = "neo-tree-hijack-cursor",
  })
end

return M
