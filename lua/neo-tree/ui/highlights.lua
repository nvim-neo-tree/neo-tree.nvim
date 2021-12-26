local vim = vim
local M = {}

function dec_to_hex(n)
  local hex = string.format("%06x", n)
  if n < 16 then
    hex = "0" .. hex
  end
  return hex
end

local normal_hl = vim.api.nvim_get_hl_by_name('Normal', true)
local success, normalnc_hl = pcall(vim.api.nvim_get_hl_by_name, 'NormalNC', true)
if not success then
  normalnc_hl = normal_hl
end

local success, float_border_hl = pcall(vim.api.nvim_get_hl_by_name, "NeoTreeFloatBorder", true)
if not success or not float_border_hl.foreground then
  local bg_hex = dec_to_hex(normalnc_hl.background)
  local fg_hex = "444444"
  vim.cmd("highlight NeoTreeFloatBorder guibg=#" .. bg_hex .. " guifg=#" .. fg_hex)
  float_border_hl = {
    background = tonumber(bg_hex, 16),
    foreground = tonumber(fg_hex, 16),
  }
end

local success, title_bar_hl = pcall(vim.api.nvim_get_hl_by_name, "NeoTreeTitleBar", true)
if not success or not title_bar_hl.background then
  vim.cmd("highlight NeoTreeTitleBar guibg=#" .. dec_to_hex(float_border_hl.foreground))
end

M.NORMAL = "NvimTreeNormal"
M.FLOAT_BORDER = "NeoTreeFloatBorder"
M.TITLE_BAR = "NeoTreeTitleBar"

return M
