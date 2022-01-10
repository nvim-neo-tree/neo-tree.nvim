local vim = vim
local Input = require("nui.input")
local NuiText = require("nui.text")
local highlights = require("neo-tree.ui.highlights")
local popups = require("neo-tree.ui.popups")

local M = {}

M.show_input = function(input, callback)
  input:mount()

  input:map("i", "<esc>", function(bufnr)
    input:unmount()
  end, { noremap = true })

  local event = require("nui.utils.autocmd").event
  input:on({ event.BufLeave, event.BufDelete }, function()
    input:unmount()
    if callback then
      callback()
    end
  end, { once = true })
end

M.input = function(message, default_value, callback, options)
  local popup_options = popups.popup_options(message, 10, options)

  local input = Input(popup_options, {
    prompt = " ",
    default_value = default_value,
    on_submit = callback,
  })

  M.show_input(input)
end

M.confirm = function(message, callback)
  local popup_options = popups.popup_options(message, 10)

  local input = Input(popup_options, {
    prompt = " y/n: ",
    on_close = function()
      callback(false)
    end,
    on_submit = function(value)
      callback(value == "y" or value == "Y")
    end,
  })

  M.show_input(input)
end

return M
