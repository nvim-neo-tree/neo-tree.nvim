local Popup = require("nui.popup")
local Text = require("nui.text")
local defaults = require("nui.utils").defaults
local is_type = require("nui.utils").is_type
local event = require("nui.utils.autocmd").event

local function init(class, popup_options, options)
  popup_options.enter = true

  popup_options.buf_options = defaults(popup_options.buf_options, {})
  popup_options.buf_options.buftype = "prompt"

  if not is_type("table", popup_options.size) then
    popup_options.size = {
      width = popup_options.size,
    }
  end

  popup_options.size.height = 1
  if popup_options.message then
    local _, count = popup_options.message:gsub('\n', '\n')
    popup_options.size.height = count + 2
  end

  local self = class.super.init(class, popup_options)

  local props = {
    default_value = defaults(options.default_value, ""),
    prompt = Text(defaults(options.prompt, "")),
    message = popup_options.message
  }

  self.input_props = props

  props.on_submit = function(value)
    local prompt_normal_mode = vim.fn.mode() == "n"

    self:unmount()

    vim.schedule(function()
      if prompt_normal_mode then
        -- NOTE: on prompt-buffer normal mode <CR> causes neovim to enter insert mode.
        --  ref: https://github.com/neovim/neovim/blob/d8f5f4d09078/src/nvim/normal.c#L5327-L5333
        vim.api.nvim_command("stopinsert")
      end

      if options.on_submit then
        options.on_submit(value)
      end
    end)
  end

  props.on_close = function()
    self:unmount()

    vim.schedule(function()
      if vim.fn.mode() == "i" then
        vim.api.nvim_command("stopinsert")
      end

      if options.on_close then
        options.on_close()
      end
    end)
  end

  if options.on_change then
    props.on_change = function()
      local value_with_prompt = vim.api.nvim_buf_get_lines(self.bufnr, -2, -1, false)[1]
      local value = string.sub(value_with_prompt, props.prompt:length() + 1)
      options.on_change(value)
    end
  end

  return self
end

local Input = setmetatable({
  name = "Input",
  super = Popup,
}, {
  __index = Popup.__index,
})

function Input:init(popup_options, options)
  return init(self, popup_options, options)
end

function Input:mount()
  local props = self.input_props

  self.super.mount(self)

  if props.on_change then
    vim.api.nvim_buf_attach(self.bufnr, false, {
      on_lines = props.on_change,
    })
  end

  if #props.default_value then
    self:on(event.InsertEnter, function()
      vim.api.nvim_feedkeys(props.default_value, "n", false)
    end, { once = true })
  end

  if props.message then
    vim.api.nvim_buf_set_lines(self.bufnr, 0, 0, false, { props.message })
  end
  vim.fn.prompt_setprompt(self.bufnr, props.prompt:content())
  if props.prompt:length() > 0 then
    vim.schedule(function()
      props.prompt:highlight(self.bufnr, self.ns_id, 1, 0)
    end)
  end

  vim.fn.prompt_setcallback(self.bufnr, props.on_submit)
  vim.fn.prompt_setinterrupt(self.bufnr, props.on_close)

  vim.api.nvim_command("startinsert!")
end

local InputClass = setmetatable({
  __index = Input,
}, {
  __call = init,
  __index = Input,
})

return InputClass
