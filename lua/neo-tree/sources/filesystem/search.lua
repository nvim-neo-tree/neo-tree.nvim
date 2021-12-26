-- This file holds all code for the search function.

local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local fs = require("neo-tree.sources.filesystem")
local M = {}

M.show_search = function(state)
  local width = vim.fn.winwidth(0) - 2
  local row = vim.api.nvim_win_get_height(0) - 2
  local popup_options = {
    relative = "win",
    position = {
      row = row,
      col = 0
    },
    size = width,
    border = {
      style = "rounded",
      highlight = "FloatBorder",
      text = {
        top = "[ Search ]",
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal",
    },
  }

  local input = Input(popup_options, {
    prompt = "> ",
    default_value = state.search_pattern,
    on_close = function()
      state.search_pattern = nil
      fs.refresh()
    end,
    on_submit = function(value)
      if value == "" then
        state.search_pattern = nil
      else
        state.search_pattern = value
      end
      fs.refresh()
    end,
    on_change = function(value)
      if #value > 2 then
        state.search_pattern = value
        fs.refresh()
      else
        if state.search_pattern then
          state.search_pattern = nil
          fs.refresh()
        end
      end
    end,
  })

  input:mount()

  input:map("i", "<esc>", function(bufnr)
    input:unmount()
  end, { noremap = true })
  local event = require("nui.utils.autocmd").event

  input:on({ event.BufLeave, event.BufDelete }, function()
    input:unmount()
  end, { once = true })
end

return M
