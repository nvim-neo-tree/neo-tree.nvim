local vim = vim
local Input = require("neo-tree.ui.custom_input")
local NuiLine = require("nui.line")
local highlights= require("neo-tree.ui.highlights")
local nt = require("neo-tree")

local M = {}

M.popup_options = function(message, min_width, override_options)
  local min_width = min_width or 30
  local width = string.len(message) + 2
  local right_padding = " "
  if width < min_width then
    right_padding = string.rep(" ", min_width - width + 1)
    width = min_width
  end

  local popup_options = {
    relative = "cursor",
    position = {
      row = 1,
      col = 0,
    },
    size = width,
    border = {
      text = {
        top = message
      },
      style = "rounded",
      highlight = highlights.FLOAT_BORDER,
    },
    win_options = {
      winhighlight = "Normal:Normal",
    },
  }

  if nt.config.popup_border_style == "NC" then
    local msgLine = NuiLine()
    msgLine:append(" " .. message .. right_padding, highlights.TITLE_BAR)
    popup_options.message = {
      msgLine
    }
    popup_options.border = {
      style = { " ", " ", " ", "▏", " ", "▔", " ", "▕" },
      highlight = highlights.FLOAT_BORDER,
    }
  end

  if override_options then
    return vim.tbl_extend("force", popup_options, override_options)
  else
    return popup_options
  end
end

M.show_input = function(input)
  input:mount()

  input:map("i", "<esc>", function(bufnr)
    input:unmount()
  end, { noremap = true })
  local event = require("nui.utils.autocmd").event

  input:on({ event.BufLeave, event.BufDelete }, function()
    input:unmount()
  end, { once = true })
end

M.input = function(message, default_value, callback)
  local popup_options = M.popup_options(message)

  local input = Input(popup_options, {
    prompt = " ",
    default_value = default_value,
    on_submit = callback,
  })

  M.show_input(input)
end

M.confirm = function(message, callback)
  local popup_options = M.popup_options(message, 10)

  local input = Input(popup_options, {
    prompt = " y/n: ",
    on_close = function ()
      callback(false)
    end,
    on_submit = function (value)
      callback(value == "y" or value == "Y")
    end,
  })

  M.show_input(input)
end

return M
