local vim = vim
local Input = require("nui.input")
local popups = require("neo-tree.ui.popups")
local utils = require("neo-tree.utils")
local events = require("neo-tree.events")

local M = {}

local should_use_popup_input = function()
  local nt = require("neo-tree")
  return utils.get_value(nt.config, "use_popups_for_input", true, false)
end

M.show_input = function(input, callback)
  input:mount()

  input:map("i", "<esc>", function()
    vim.cmd("stopinsert")
    input:unmount()
  end, { noremap = true })

  input:map("n", "<esc>", function()
    input:unmount()
  end, { noremap = true })

  input:map("n", "q", function()
    input:unmount()
  end, { noremap = true })

  input:map("i", "<C-w>", "<C-S-w>", { noremap = true })

  local event = require("nui.utils.autocmd").event
  input:on({ event.BufLeave, event.BufDelete }, function()
    input:unmount()
    if callback then
      callback()
    end
  end, { once = true })

  if input.prompt_type ~= "confirm" then
    vim.schedule(function()
      events.fire_event(events.NEO_TREE_POPUP_INPUT_READY, {
        bufnr = input.bufnr,
        winid = input.winid,
      })
    end)
  end
end

M.input = function(message, default_value, callback, options, completion)
  if should_use_popup_input() then
    local popup_options = popups.popup_options(message, 10, options)

    local input = Input(popup_options, {
      prompt = " ",
      default_value = default_value,
      on_submit = callback,
    })

    M.show_input(input)
  else
    local opts = {
      prompt = message .. "\n",
      default = default_value,
    }
    if vim.opt.cmdheight:get() == 0 then
      -- NOTE: I really don't know why but letters before the first '\n' is not rendered execpt in noice.nvim
      --       when vim.opt.cmdheight = 0 <2023-10-24, pysan3>
      opts.prompt = "Neo-tree Popup\n" .. opts.prompt
    end
    if completion then
      opts.completion = completion
    end
    vim.ui.input(opts, callback)
  end
end

M.confirm = function(message, callback)
  if should_use_popup_input() then
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

    input.prompt_type = "confirm"
    M.show_input(input)
  else
    callback(vim.fn.confirm(message, "&Yes\n&No") == 1)
  end
end

return M
