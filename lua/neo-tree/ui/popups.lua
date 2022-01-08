
local vim = vim
local Input = require("nui.input")
local NuiText = require("nui.text")
local highlights= require("neo-tree.ui.highlights")

local M = {}

M.popup_options = function(title, min_width, override_options)
  local min_width = min_width or 30
  local width = string.len(title) + 2
  local right_padding = " "
  if width < min_width then
    right_padding = string.rep(" ", min_width - width + 1)
    width = min_width
  end

  local nt = require("neo-tree")
  local popup_border_style = nt.config.popup_border_style 
  local popup_options = {
    relative = "cursor",
    position = {
      row = 1,
      col = 0,
    },
    size = width,
    border = {
      text = {
        top = title
      },
      style = popup_border_style,
      highlight = highlights.FLOAT_BORDER,
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:" .. highlights.FLOAT_BORDER,
    },
  }

  if popup_border_style == "NC" then
    local blank = NuiText(" ", highlights.TITLE_BAR)
    local text = NuiText(" " .. title .. " ", highlights.TITLE_BAR)
    popup_options.border = {
      style = { "▕", blank, "▏", "▏", " ", "▔", " ", "▕" },
      highlight = highlights.FLOAT_BORDER,
      text = {
        top = text,
        top_align = "left"
      },
    }
  end

  if override_options then
    return vim.tbl_extend("force", popup_options, override_options)
  else
    return popup_options
  end
end

return M
