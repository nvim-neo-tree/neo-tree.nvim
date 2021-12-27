-- This file holds all code for the search function.

local vim = vim
local Input = require("neo-tree.ui.custom_input")
local event = require("nui.utils.autocmd").event
local fs = require("neo-tree.sources.filesystem")
local inputs = require("neo-tree.ui.inputs")

local M = {}

M.show_filter = function(state)
  local width = vim.fn.winwidth(0) - 2
  local row = vim.api.nvim_win_get_height(0) - 2
  local popup_options = inputs.popup_options("Enter Filter Pattern:", width, {
    relative = "win",
    position = {
      row = row,
      col = 0
    },
    size = width,
  })

  local input = Input(popup_options, {
    prompt = " ",
    default_value = state.search_pattern,
    --on_close = function()
    --  if state.search_pattern then
    --    state.search_pattern = nil
    --    fs.refresh()
    --  end
    --end,
    on_submit = function(value)
      if value == "" then
        state.search_pattern = nil
      else
        state.search_pattern = value
      end
      fs.refresh()
    end,
    --this can be bad in a deep folder structure
    --on_change = function(value)
    --  if value and #value > 2 then
    --    state.search_pattern = value
    --    fs.refresh()
    --  end
    --end,
  })

  inputs.show_input(input)
end

return M
