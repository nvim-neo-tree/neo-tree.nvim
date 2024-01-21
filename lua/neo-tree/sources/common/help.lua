local Popup = require("nui.popup")
local NuiLine = require("nui.line")
local utils = require("neo-tree.utils")
local popups = require("neo-tree.ui.popups")
local highlights = require("neo-tree.ui.highlights")
local M = {}

local add_text = function(text, highlight)
  local line = NuiLine()
  line:append(text, highlight)
  return line
end

local get_sub_keys = function(state, prefix_key)
  local keys = utils.get_keys(state.resolved_mappings, true)
  if prefix_key then
    local len = prefix_key:len()
    local sub_keys = {}
    for _, key in ipairs(keys) do
      if #key > len and key:sub(1, len) == prefix_key then
        table.insert(sub_keys, key)
      end
    end
    return sub_keys
  else
    return keys
  end
end

local function key_minus_prefix(key, prefix)
  if prefix then
    return key:sub(prefix:len() + 1)
  else
    return key
  end
end

---Shows a help screen for the mapped commands when will execute those commands
---when the corresponding key is pressed.
---@param state table state of the source.
---@param title string if this is a sub-menu for a multi-key mapping, the title for the window.
---@param prefix_key string if this is a sub-menu, the start of tehe multi-key mapping
M.show = function(state, title, prefix_key)
  local tree_width = vim.api.nvim_win_get_width(state.winid)
  local keys = get_sub_keys(state, prefix_key)

  local lines = { add_text("") }
  lines[1] = add_text(" Press the corresponding key to execute the command.", "Comment")
  lines[2] = add_text("               Press <Esc> to cancel.", "Comment")
  lines[3] = add_text("")
  local header = NuiLine()
  header:append(string.format(" %14s", "KEY(S)"), highlights.ROOT_NAME)
  header:append("    ", highlights.DIM_TEXT)
  header:append("COMMAND", highlights.ROOT_NAME)
  lines[4] = header
  local max_width = #lines[1]:content()
  for _, key in ipairs(keys) do
    local value = state.resolved_mappings[key]
    local nline = NuiLine()
    nline:append(string.format(" %14s", key_minus_prefix(key, prefix_key)), highlights.FILTER_TERM)
    nline:append(" -> ", highlights.DIM_TEXT)
    nline:append(value.text, highlights.NORMAL)
    local line = nline:content()
    if #line > max_width then
      max_width = #line
    end
    table.insert(lines, nline)
  end

  local width = math.min(60, max_width + 1)

  if state.current_position == "right" then
    col = vim.o.columns - tree_width - width - 1
  else
    col = tree_width - 1
  end

  local options = {
    position = {
      row = 2,
      col = col,
    },
    size = {
      width = width,
      height = #keys + 5,
    },
    enter = true,
    focusable = true,
    zindex = 50,
    relative = "editor",
  }

  local popup_max_height = function()
    local lines = vim.o.lines
    local cmdheight = vim.o.cmdheight
    -- statuscolumn
    local statuscolumn_lines = 0
    local laststatus = vim.o.laststatus
    if laststatus ~= 0 then
      local windows = vim.api.nvim_tabpage_list_wins(0)
      if (laststatus == 1 and #windows > 1) or laststatus > 1 then
        statuscolumn_lines = 1
      end
    end
    -- tabs
    local tab_lines = 0
    local showtabline = vim.o.showtabline
    if showtabline ~= 0 then
      local tabs = vim.api.nvim_list_tabpages()
      if (showtabline == 1 and #tabs > 1) or showtabline == 2 then
        tab_lines = 1
      end
    end
    return lines - cmdheight - statuscolumn_lines - tab_lines - 1
  end
  local max_height = popup_max_height()
  if options.size.height > max_height then
    options.size.height = max_height
  end

  local title = title or "Neotree Help"
  local options = popups.popup_options(title, width, options)
  local popup = Popup(options)
  popup:mount()

  popup:map("n", "<esc>", function()
    popup:unmount()
  end, { noremap = true })

  local event = require("nui.utils.autocmd").event
  popup:on({ event.BufLeave, event.BufDelete }, function()
    popup:unmount()
  end, { once = true })

  for _, key in ipairs(keys) do
    -- map everything except for <escape>
    if string.match(key:lower(), "^<esc") == nil then
      local value = state.resolved_mappings[key]
      popup:map("n", key_minus_prefix(key, prefix_key), function()
        popup:unmount()
        vim.api.nvim_set_current_win(state.winid)
        value.handler()
      end)
    end
  end

  for i, line in ipairs(lines) do
    line:render(popup.bufnr, -1, i)
  end
end

return M
