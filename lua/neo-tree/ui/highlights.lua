---@enum NeotreeHighlightGroupName
local enum = {
  BUFFER_NUMBER = "NeoTreeBufferNumber",
  CURSOR_LINE = "NeoTreeCursorLine",
  DIM_TEXT = "NeoTreeDimText",
  DIRECTORY_ICON = "NeoTreeDirectoryIcon",
  DIRECTORY_NAME = "NeoTreeDirectoryName",
  DOTFILE = "NeoTreeDotfile",
  FADE_TEXT_1 = "NeoTreeFadeText1",
  FADE_TEXT_2 = "NeoTreeFadeText2",
  FILE_ICON = "NeoTreeFileIcon",
  FILE_NAME = "NeoTreeFileName",
  FILE_NAME_OPENED = "NeoTreeFileNameOpened",
  FILE_STATS = "NeoTreeFileStats",
  FILE_STATS_HEADER = "NeoTreeFileStatsHeader",
  FILTER_TERM = "NeoTreeFilterTerm",
  FLOAT_BORDER = "NeoTreeFloatBorder",
  FLOAT_NORMAL = "NeoTreeFloatNormal",
  FLOAT_TITLE = "NeoTreeFloatTitle",
  GIT_ADDED = "NeoTreeGitAdded",
  GIT_CONFLICT = "NeoTreeGitConflict",
  GIT_DELETED = "NeoTreeGitDeleted",
  GIT_IGNORED = "NeoTreeGitIgnored",
  GIT_MODIFIED = "NeoTreeGitModified",
  GIT_RENAMED = "NeoTreeGitRenamed",
  GIT_STAGED = "NeoTreeGitStaged",
  GIT_UNTRACKED = "NeoTreeGitUntracked",
  GIT_UNSTAGED = "NeoTreeGitUnstaged",
  HIDDEN_BY_NAME = "NeoTreeHiddenByName",
  MESSAGE = "NeoTreeMessage",
  MODIFIED = "NeoTreeModified",
  NORMAL = "NeoTreeNormal",
  NORMALNC = "NeoTreeNormalNC",
  SIGNCOLUMN = "NeoTreeSignColumn",
  STATUS_LINE = "NeoTreeStatusLine",
  STATUS_LINE_NC = "NeoTreeStatusLineNC",
  TAB_ACTIVE = "NeoTreeTabActive",
  TAB_INACTIVE = "NeoTreeTabInactive",
  TAB_SEPARATOR_ACTIVE = "NeoTreeTabSeparatorActive",
  TAB_SEPARATOR_INACTIVE = "NeoTreeTabSeparatorInactive",
  VERTSPLIT = "NeoTreeVertSplit",
  WINSEPARATOR = "NeoTreeWinSeparator",
  END_OF_BUFFER = "NeoTreeEndOfBuffer",
  ROOT_NAME = "NeoTreeRootName",
  SYMBOLIC_LINK_TARGET = "NeoTreeSymbolicLinkTarget",
  TITLE_BAR = "NeoTreeTitleBar",
  INDENT_MARKER = "NeoTreeIndentMarker",
  EXPANDER = "NeoTreeExpander",
  WINDOWS_HIDDEN = "NeoTreeWindowsHidden",
  PREVIEW = "NeoTreePreview",
}

---@class NeotreeHighlightGroupValue
---@field foreground number?
---@field background number?
---@field gui string?
---@field bold boolean?
---@field italic boolean?
---@field underline boolean?
---@field undercurl boolean?

local M = enum

---@type table<string, NeotreeHighlightGroupValue>
M.faded_highlight_group_cache = {}

---@type integer
M.ns_id = vim.api.nvim_create_namespace("neo-tree.nvim")

---Create a hex representation of `n`
---@param n number|any # Decimal integer or return itself if type(n) ~= "number"
---@return string
local function dec_to_highlight(n)
  if type(n) == "string" and #n > 0 then
    local val = tonumber(n, 16)
    if type(val) == "number" then
      n = val
    end
  end
  if type(n) ~= "number" then
    return n
  end
  return "#" .. string.format("%06x", n)
end

---If the given highlight group is not defined, define it.
---@param hl_group_name string # The name of the highlight group.
---@param link_to_if_exists table # A list of highlight groups to link to, in order of priority. The first one that exists will be used.
---@param background string|number|nil # The background color to use, in hex, if the highlight group is not defined and it is not linked to another group.
---@param foreground string|number|nil # The foreground color to use, in hex, if the highlight group is not defined and it is not linked to another group.
---@param gui string|number|nil # The gui to use, if the highlight group is not defined and it is not linked to another group.
---@return NeotreeHighlightGroupValue # The highlight group values.
M.create_highlight_group = function(hl_group_name, link_to_if_exists, background, foreground, gui)
  local success, hl_group = pcall(vim.api.nvim_get_hl_by_name, hl_group_name, true)
  ---@cast hl_group NeotreeHighlightGroupValue
  if success and hl_group.foreground and hl_group.background then
    return hl_group
  end
  for _, link_to in ipairs(link_to_if_exists) do
    success, hl_group = pcall(vim.api.nvim_get_hl_by_name, link_to, true)
    ---@cast hl_group NeotreeHighlightGroupValue
    if success then
      local new_group_has_settings = background or foreground or gui
      local link_to_has_settings = hl_group.foreground or hl_group.background
      if link_to_has_settings or not new_group_has_settings then
        vim.cmd(string.format([[highlight default link %s %s]], hl_group_name, link_to))
        return hl_group
      end
    end
  end
  ---@type string[]
  local cmds = {}
  if background then
    table.insert(cmds, "guibg=" .. dec_to_highlight(background))
  end
  table.insert(cmds, "guifg=" .. (dec_to_highlight(foreground) or "NONE"))
  if gui then
    table.insert(cmds, "gui=" .. dec_to_highlight(gui))
  end
  if #cmds > 0 then
    vim.cmd("highlight default " .. hl_group_name .. " " .. table.concat(cmds, " "))
  end
  return {
    background = background,
    foreground = foreground,
  }
end

---Blend guifg and guibg with the ratio of `fade_percentage`
---@param hl_group_name string
---@param fade_percentage number
---@return NeotreeHighlightGroupValue
local calculate_faded_highlight_group = function(hl_group_name, fade_percentage)
  local normal = vim.api.nvim_get_hl_by_name("Normal", true)
  ---@cast normal NeotreeHighlightGroupValue
  if type(normal.foreground) ~= "number" then
    if vim.api.nvim_get_option("background") == "dark" then
      normal.foreground = 0xffffff
    else
      normal.foreground = 0x000000
    end
  end
  if type(normal.background) ~= "number" then
    if vim.api.nvim_get_option("background") == "dark" then
      normal.background = 0x000000
    else
      normal.background = 0xffffff
    end
  end
  local foreground = dec_to_highlight(normal.foreground)
  local background = dec_to_highlight(normal.background)

  local hl_group = vim.api.nvim_get_hl_by_name(hl_group_name, true) or {}
  ---@cast hl_group NeotreeHighlightGroupValue
  if type(hl_group.foreground) == "number" then
    foreground = dec_to_highlight(hl_group.foreground)
  end
  if type(hl_group.background) == "number" then
    background = dec_to_highlight(hl_group.background)
  end

  local gui_accum = {}
  if hl_group.bold then
    table.insert(gui_accum, "bold")
  end
  if hl_group.italic then
    table.insert(gui_accum, "italic")
  end
  if hl_group.underline then
    table.insert(gui_accum, "underline")
  end
  if hl_group.undercurl then
    table.insert(gui_accum, "undercurl")
  end
  if #gui_accum > 0 then
    hl_group.gui = table.concat(gui_accum, ",")
  end

  local f_red = tonumber(foreground:sub(2, 3), 16)
  local f_green = tonumber(foreground:sub(4, 5), 16)
  local f_blue = tonumber(foreground:sub(6, 7), 16)

  local b_red = tonumber(background:sub(2, 3), 16)
  local b_green = tonumber(background:sub(4, 5), 16)
  local b_blue = tonumber(background:sub(6, 7), 16)

  local red = (f_red * fade_percentage) + (b_red * (1 - fade_percentage))
  local green = (f_green * fade_percentage) + (b_green * (1 - fade_percentage))
  local blue = (f_blue * fade_percentage) + (b_blue * (1 - fade_percentage))

  hl_group.foreground = tonumber(string.format("%02x%02x%02x", red, green, blue), 16)
  return hl_group
end

---@param hl_group_name string
---@param fade_percentage number
---@return string # Name of faded highlight group
M.get_faded_highlight_group = function(hl_group_name, fade_percentage)
  if type(hl_group_name) ~= "string" then
    error("hl_group_name must be a string")
  end
  if type(fade_percentage) ~= "number" then
    error("hl_group_name must be a number")
  end
  if fade_percentage < 0 or fade_percentage > 1 then
    error("fade_percentage must be between 0 and 1")
  end

  local key = hl_group_name .. "_" .. tostring(math.floor(fade_percentage * 100))
  if M.faded_highlight_group_cache[key] then
    return key
  end
  local faded = calculate_faded_highlight_group(hl_group_name, fade_percentage)
  M.create_highlight_group(key, {}, faded.background, faded.foreground, faded.gui)
  M.faded_highlight_group_cache[key] = faded
  return key
end

M.setup = function()
  -- Reset this here in case of color scheme change
  M.faded_highlight_group_cache = {}

  local normal_hl = M.create_highlight_group(M.NORMAL, { "Normal" })
  local normalnc_hl = M.create_highlight_group(M.NORMALNC, { "NormalNC", M.NORMAL })

  M.create_highlight_group(M.SIGNCOLUMN, { "SignColumn", M.NORMAL })

  M.create_highlight_group(M.STATUS_LINE, { "StatusLine" })
  M.create_highlight_group(M.STATUS_LINE_NC, { "StatusLineNC" })

  M.create_highlight_group(M.VERTSPLIT, { "VertSplit" })
  M.create_highlight_group(M.WINSEPARATOR, { "WinSeparator" })

  M.create_highlight_group(M.END_OF_BUFFER, { "EndOfBuffer" })

  local float_border_hl =
    M.create_highlight_group(M.FLOAT_BORDER, { "FloatBorder" }, normalnc_hl.background, "#444444")

  M.create_highlight_group(M.FLOAT_NORMAL, { "NormalFloat", M.NORMAL })

  M.create_highlight_group(M.FLOAT_TITLE, {}, float_border_hl.background, normal_hl.foreground)

  local title_fg = normal_hl.background
  if title_fg == float_border_hl.foreground then
    title_fg = normal_hl.foreground
  end
  M.create_highlight_group(M.TITLE_BAR, {}, float_border_hl.foreground, title_fg)

  local dim_text = calculate_faded_highlight_group("NeoTreeNormal", 0.3)

  M.create_highlight_group(M.BUFFER_NUMBER, { "SpecialChar" })
  -- M.create_highlight_group(M.DIM_TEXT, {}, nil, "#505050")
  M.create_highlight_group(M.MESSAGE, {}, nil, dim_text.foreground, "italic")
  M.create_highlight_group(M.FADE_TEXT_1, {}, nil, "#626262")
  M.create_highlight_group(M.FADE_TEXT_2, {}, nil, "#444444")
  M.create_highlight_group(M.DOTFILE, {}, nil, "#626262")
  M.create_highlight_group(M.HIDDEN_BY_NAME, { M.DOTFILE }, nil, nil)
  M.create_highlight_group(M.CURSOR_LINE, { "CursorLine" }, nil, nil, "bold")
  M.create_highlight_group(M.DIM_TEXT, {}, nil, dim_text.foreground)
  M.create_highlight_group(M.DIRECTORY_NAME, { "Directory" }, "NONE", "NONE")
  M.create_highlight_group(M.DIRECTORY_ICON, { "Directory" }, nil, "#73cef4")
  M.create_highlight_group(M.FILE_ICON, { M.DIRECTORY_ICON })
  M.create_highlight_group(M.FILE_NAME, {}, "NONE", "NONE")
  M.create_highlight_group(M.FILE_NAME_OPENED, {}, nil, nil, "bold")
  M.create_highlight_group(M.SYMBOLIC_LINK_TARGET, { M.FILE_NAME })
  M.create_highlight_group(M.FILTER_TERM, { "SpecialChar", "Normal" })
  M.create_highlight_group(M.ROOT_NAME, {}, nil, nil, "bold,italic")
  M.create_highlight_group(M.INDENT_MARKER, { M.DIM_TEXT })
  M.create_highlight_group(M.EXPANDER, { M.DIM_TEXT })
  M.create_highlight_group(M.MODIFIED, {}, nil, "#d7d787")
  M.create_highlight_group(M.WINDOWS_HIDDEN, { M.DOTFILE }, nil, nil)
  M.create_highlight_group(M.PREVIEW, { "Search" }, nil, nil)

  M.create_highlight_group(M.GIT_ADDED, { "GitGutterAdd", "GitSignsAdd" }, nil, "#5faf5f")
  M.create_highlight_group(M.GIT_DELETED, { "GitGutterDelete", "GitSignsDelete" }, nil, "#ff5900")
  M.create_highlight_group(M.GIT_MODIFIED, { "GitGutterChange", "GitSignsChange" }, nil, "#d7af5f")
  local conflict = M.create_highlight_group(M.GIT_CONFLICT, {}, nil, "#ff8700", "italic,bold")
  M.create_highlight_group(M.GIT_IGNORED, { M.DOTFILE }, nil, nil)
  M.create_highlight_group(M.GIT_RENAMED, { M.GIT_MODIFIED }, nil, nil)
  M.create_highlight_group(M.GIT_STAGED, { M.GIT_ADDED }, nil, nil)
  M.create_highlight_group(M.GIT_UNSTAGED, { M.GIT_CONFLICT }, nil, nil)
  M.create_highlight_group(M.GIT_UNTRACKED, {}, nil, conflict.foreground, "italic")

  M.create_highlight_group(M.TAB_ACTIVE, {}, nil, nil, "bold")
  M.create_highlight_group(M.TAB_INACTIVE, {}, "#141414", "#777777")
  M.create_highlight_group(M.TAB_SEPARATOR_ACTIVE, {}, nil, "#0a0a0a")
  M.create_highlight_group(M.TAB_SEPARATOR_INACTIVE, {}, "#141414", "#101010")

  local faded_normal = calculate_faded_highlight_group("NeoTreeNormal", 0.4)
  M.create_highlight_group(M.FILE_STATS, {}, nil, faded_normal.foreground)

  local faded_root = calculate_faded_highlight_group("NeoTreeRootName", 0.5)
  M.create_highlight_group(M.FILE_STATS_HEADER, {}, nil, faded_root.foreground, faded_root.gui)
end

return M
