local vim = vim
local M = {}

function dec_to_hex(n)
  local hex = string.format("%06x", n)
  if n < 16 then
    hex = "0" .. hex
  end
  return hex
end

---If the given highlight group is not defined, define it.
---@param hl_group_name string The name of the highlight group.
---@param link_to_if_exists table A list of highlight groups to link to, in 
--order of priority. The first one that exists will be used.
---@param background string The background color to use, in hex, if the highlight group
--is not defined and it is not linked to another group.
---@param foreground string The foreground color to use, in hex, if the highlight group
--is not defined and it is not linked to another group.
---@return table table The highlight group values.
local function set_hl_group(hl_group_name, link_to_if_exists, background, foreground)
  local success, hl_group = pcall(vim.api.nvim_get_hl_by_name, hl_group_name, true)
  if not success or not hl_group.foreground or not hl_group.background then
    for _, link_to in ipairs(link_to_if_exists) do
      success, hl_group = pcall(vim.api.nvim_get_hl_by_name, link_to, true)
      if success and (hl_group.foreground or hl_group.background) then
        vim.cmd("highlight link " .. hl_group_name .. " " .. link_to)
        return hl_group
      end
    end

    local cmd = "highlight " .. hl_group_name
    if background then
      cmd = cmd .. " guibg=#" .. background
    end
    if foreground then
      cmd = cmd .. " guifg=#" .. foreground
    end
    vim.cmd(cmd)
    return {
      background = background and tonumber(background, 16) or nil,
      foreground = foreground and tonumber(foreground, 16) or nil,
    }
  end
end

local normal_hl = vim.api.nvim_get_hl_by_name('Normal', true)
local success, normalnc_hl = pcall(vim.api.nvim_get_hl_by_name, 'NormalNC', true)
if not success then
  normalnc_hl = normal_hl
end

local float_border_hl = set_hl_group( 'NeoTreeFloatBorder',
  { 'FloatBorder' },
  dec_to_hex(normalnc_hl.background), '444444')

set_hl_group("NeoTreeTitleBar",
  {},
  dec_to_hex(float_border_hl.background))

set_hl_group("NeoTreeGitAdded",
  { "GitGutterAdd", "GitSignsAdd" },
  nil, '5faf5f')

set_hl_group("NeoTreeGitModified",
  { "GitGutterChange", "GitSignsChange"  },
  nil, 'd7af5f')

M.NORMAL = "NvimTreeNormal"
M.FLOAT_BORDER = "NeoTreeFloatBorder"
M.TITLE_BAR = "NeoTreeTitleBar"

return M
