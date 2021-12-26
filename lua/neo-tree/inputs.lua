local vim = vim
local Input = require("neo-tree.custom_input")

local M = {}

M.popup_options = function(message, min_width, override_options)
  local min_width = min_width or 30
  local width = string.len(message) + 4
  if width < min_width then
    width = min_width
  end

  local popup_options = {
    message = " " .. message,
    relative = "cursor",
    position = {
      row = 1,
      col = 0,
    },
    size = width,
    border = {
      --style = {
      --  top_left    = "╭", top    = "─",    top_right = "╮",
      --  left        = "│",                      right = "│",
      --  bottom_left = "╰", bottom = "─", bottom_right = "╯",
      --},
      style = { " ", "▁", " ", "▏", " ", "▔", " ", "▕" },
      highlight = "FloatBorder",
    },
    win_options = {
      winhighlight = "Normal:Normal",
    },
  }

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
