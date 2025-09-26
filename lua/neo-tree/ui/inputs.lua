local NuiInput = require("nui.input")
local nt = require("neo-tree")
local popups = require("neo-tree.ui.popups")
local events = require("neo-tree.events")

local M = {}

---@param input NuiInput
---@param callback function?
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

  input:on({ event.WinEnter }, function()
    vim.cmd.startinsert()
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

---@param message string
---@param default_value string?
---@param callback function
---@param options nui_popup_options?
---@param completion string?
M.input = function(message, default_value, callback, options, completion)
  if nt.config.use_popups_for_input then
    local popup_options = popups.popup_options(message, 10, options)

    local input = NuiInput(popup_options, {
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
      -- NOTE: I really don't know why but letters before the first '\n' is not rendered except in noice.nvim
      --       when vim.opt.cmdheight = 0 <2023-10-24, pysan3>
      opts.prompt = "Neo-tree Popup\n" .. opts.prompt
    end
    if completion then
      opts.completion = completion
    end
    vim.ui.input(opts, callback)
  end
end

---Blocks if callback is omitted
---@param message string
---@param callback? fun(confirmed: boolean)
---@return boolean? confirmed_if_no_callback
M.confirm = function(message, callback)
  if callback then
    if nt.config.use_popups_for_input then
      local popup_options = popups.popup_options(message, 10)

      ---@class NuiInput
      local input = NuiInput(popup_options, {
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
  else
    return vim.fn.confirm(message, "&Yes\n&No") == 1
  end
end

return M
