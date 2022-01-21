-- This file holds all code for the search function.

local vim = vim
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local fs = require("neo-tree.sources.filesystem")
local inputs = require("neo-tree.ui.inputs")
local popups = require("neo-tree.ui.popups")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")

local M = {}

M.show_filter = function(state, search_as_you_type)
  local width = vim.fn.winwidth(0) - 2
  local row = vim.api.nvim_win_get_height(0) - 3
  local popup_options = popups.popup_options("Enter Filter Pattern:", width, {
    relative = "win",
    position = {
      row = row,
      col = 0,
    },
    size = width,
  })

  local has_pre_search_folders = utils.truthy(state.open_folders_before_search)
  if not has_pre_search_folders then
    log.trace("No search or pre-search folders, recording pre-search folders now")
    state.open_folders_before_search = renderer.get_expanded_nodes(state.tree)
  end

  local waiting_for_default_value = utils.truthy(state.search_pattern)
  local input = Input(popup_options, {
    prompt = " ",
    default_value = state.search_pattern,
    on_submit = function(value)
      if value == "" then
        fs.reset_search()
      else
        state.search_pattern = value
        fs.refresh(function()
          -- focus first file
          local nodes = renderer.get_all_visible_nodes(state.tree)
          for _, node in ipairs(nodes) do
            if node.type == "file" then
              renderer.focus_node(state, node:get_id(), false)
              break
            end
          end
        end)
      end
    end,
    --this can be bad in a deep folder structure
    on_change = function(value)
      if not search_as_you_type then
        return
      end
      -- apparently when a default value is set, on_change fires for every character
      if waiting_for_default_value then
        if #value < #state.search_pattern then
          return
        else
          waiting_for_default_value = false
        end
      end
      if value == state.search_pattern then
        return
      elseif value == nil then
        return
      elseif value == "" then
        if state.search_pattern == nil then
          return
        end
        log.trace("Resetting search in on_change")
        local original_open_folders = nil
        if type(state.open_folders_before_search) == "table" then
          original_open_folders = utils.table_copy(state.open_folders_before_search)
        end
        fs.reset_search()
        state.open_folders_before_search = original_open_folders
      else
        log.trace("Setting search in on_change to: " .. value)
        state.search_pattern = value
        manager.refresh("filesystem")
      end
    end,
  })

  input:mount()

  input:map("i", "<esc>", function(bufnr)
    input:unmount()
  end, { noremap = true })

  input:on({ event.BufLeave, event.BufDelete }, function()
    input:unmount()
  end, { once = true })
end

return M
