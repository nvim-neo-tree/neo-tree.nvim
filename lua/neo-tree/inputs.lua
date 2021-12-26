local Input = require("nui.input")
local event = require("nui.utils.autocmd").event

local M = {}

M.input = function(title, default_value, callback)
  local width = string.len(title) + 6
  if width < 30 then
    width = 30
  end

  local popup_options = {
    relative = "cursor",
    position = {
      row = 1,
      col = 0,
    },
    size = width,
    border = {
      style = "rounded",
      highlight = "FloatBorder",
      text = {
        top = "[ " .. title .. " ]",
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal",
    },
  }

  local input = Input(popup_options, {
    prompt = "> ",
    default_value = default_value,
    on_submit = callback,
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

M.confirm = function(title, callback)
  local width = string.len(title) + 6

  local popup_options = {
    relative = "cursor",
    position = {
      row = 1,
      col = 0,
    },
    size = width,
    border = {
      style = "rounded",
      highlight = "FloatBorder",
      text = {
        top = "[ " .. title .. " ]",
        top_align = "left",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal",
    },
  }

  local input = Input(popup_options, {
    prompt = "y/n: ",
    on_close = function ()
      callback(false)
    end,
    on_submit = function (value)
      callback(value == "y" or value == "Y")
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
