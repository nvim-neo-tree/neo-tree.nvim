-- This file holds all code for the search function.

local vim = vim
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local fs = require("neo-tree.sources.filesystem")
local inputs = require("neo-tree.ui.inputs")
local renderer = require("neo-tree.ui.renderer")

local M = {}

M.show_filter = function(state, search_as_you_type)
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

  if not state.search_pattern then
    state.open_folders_before_search = renderer.get_expanded_nodes(state.tree)
  end

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
        fs.reset_search()
      else
        state.search_pattern = value
        fs.refresh()
      end
    end,
    --this can be bad in a deep folder structure
    on_change = function(value)
      if not search_as_you_type then
        return
      end
      if value == state.search_pattern then
        return
      end
      if value == nil or value == "" then
        fs.reset_search()
      else
        state.search_pattern = value
        fs.refresh()
      end
    end,
  })

  inputs.show_input(input)
end

return M
