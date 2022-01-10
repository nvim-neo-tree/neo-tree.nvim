local vim = vim
local M = {}

M.BUFFER_NUMBER = "NeoTreeBufferNumber"
M.CURSOR_LINE = "NeoTreeCursorLine"
M.DIM_TEXT = "NeoTreeDimText"
M.DIRECTORY_NAME = "NeoTreeDirectoryName"
M.DIRECTORY_ICON = "NeoTreeDirectoryIcon"
M.FILE_ICON = "NeoTreeFileIcon"
M.FILE_NAME = "NeoTreeFileName"
M.FILE_NAME_OPENED = "NeoTreeFileNameOpened"
M.FILTER_TERM = "NeoTreeFilterTerm"
M.FLOAT_BORDER = "NeoTreeFloatBorder"
M.GIT_ADDED = "NeoTreeGitAdded"
M.GIT_CONFLICT = "NeoTreeGitConflict"
M.GIT_MODIFIED = "NeoTreeGitModified"
M.GIT_UNTRACKED = "NeoTreeGitUntracked"
M.NORMAL = "NeoTreeNormal"
M.NORMALNC = "NeoTreeNormalNC"
M.ROOT_NAME = "NeoTreeRootName"
M.TITLE_BAR = "NeoTreeTitleBar"

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
local function create_highlight_group(hl_group_name, link_to_if_exists, background, foreground, gui)
  local success, hl_group = pcall(vim.api.nvim_get_hl_by_name, hl_group_name, true)
  if not success or not hl_group.foreground or not hl_group.background then
    for _, link_to in ipairs(link_to_if_exists) do
      success, hl_group = pcall(vim.api.nvim_get_hl_by_name, link_to, true)
      if success and (hl_group.foreground or hl_group.background) then
        vim.cmd("highlight default link " .. hl_group_name .. " " .. link_to)
        return hl_group
      end
    end

    if type(background) == "number" then
      background = dec_to_hex(background)
    end
    if type(foreground) == "number" then
      foreground = dec_to_hex(foreground)
    end

    local cmd = "highlight default " .. hl_group_name
    if background then
      cmd = cmd .. " guibg=#" .. background
    end
    if foreground then
      cmd = cmd .. " guifg=#" .. foreground
    else
      cmd = cmd .. " guifg=NONE"
    end
    if gui then
      cmd = cmd .. " gui=" .. gui
    end
    vim.cmd(cmd)

    return {
      background = background and tonumber(background, 16) or nil,
      foreground = foreground and tonumber(foreground, 16) or nil,
    }
  end
end

local normal_hl = create_highlight_group(M.NORMAL, { "Normal" })
local normalnc_hl = create_highlight_group(M.NORMALNC, { "NormalNC", M.NORMAL })

local float_border_hl = create_highlight_group(M.FLOAT_BORDER, { "FloatBorder" }, normalnc_hl.background, "444444")

create_highlight_group(M.TITLE_BAR, {}, float_border_hl.foreground, nil)

create_highlight_group(M.GIT_ADDED, { "GitGutterAdd", "GitSignsAdd" }, nil, "5faf5f")

create_highlight_group(M.GIT_CONFLICT, { "GitGutterDelete", "GitSignsDelete" }, nil, "ff5900")

local modified = create_highlight_group(M.GIT_MODIFIED, { "GitGutterChange", "GitSignsChange" }, nil, "d7af5f")

create_highlight_group(M.GIT_UNTRACKED, {}, nil, modified.foreground, "italic")

create_highlight_group(M.BUFFER_NUMBER, { "SpecialChar" })
create_highlight_group(M.DIM_TEXT, {}, nil, "505050")
create_highlight_group(M.CURSOR_LINE, { "CursorLine" })
create_highlight_group(M.DIRECTORY_NAME, {}, "NONE", "NONE")
create_highlight_group(M.DIRECTORY_ICON, { "TabLineSel" }, nil, "#73cef4")
create_highlight_group(M.FILE_ICON, { M.DIRECTORY_ICON })
create_highlight_group(M.FILE_NAME, {}, "NONE", "NONE")
create_highlight_group(M.FILE_NAME_OPENED, {}, nil, nil, "bold")
create_highlight_group(M.FILTER_TERM, { "SpecialChar", "Normal" })
create_highlight_group(M.ROOT_NAME, {}, nil, nil, "bold,italic")

return M
