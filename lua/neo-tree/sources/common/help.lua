local Popup = require("nui.popup")
local NuiLine = require("nui.line")
local utils = require("neo-tree.utils")
local popups = require("neo-tree.ui.popups")
local highlights = require("neo-tree.ui.highlights")
local M = {}

---@param text string
---@param highlight string?
---@return NuiLine
local add_text = function(text, highlight)
  local line = NuiLine()
  line:append(text, highlight)
  return line
end

---@param state neotree.State
---@param prefix_key string?
local get_sub_keys = function(state, prefix_key)
  local keys = utils.get_keys(state.resolved_mappings)
  if not prefix_key then
    return keys
  end

  local len = prefix_key:len()
  local sub_keys = {}
  for _, key in ipairs(keys) do
    if #key > len and key:sub(1, len) == prefix_key then
      table.insert(sub_keys, key)
    end
  end
  return sub_keys
end

---@param key string
---@param prefix string?
local function key_minus_prefix(key, prefix)
  if prefix then
    return key:sub(prefix:len() + 1)
  else
    return key
  end
end

---@class neotree.Help.Mapping
---@field key string
---@field mapping neotree.State.ResolvedMapping

---@alias neotree.Help.Sorter fun(a: neotree.Help.Mapping, b: neotree.Help.Mapping):boolean

---@type neotree.Help.Sorter
local default_help_sort = function(a, b)
  return a.key < b.key
end

---Shows a help screen for the mapped commands when will execute those commands
---when the corresponding key is pressed.
---@param state neotree.State state of the source.
---@param title string? if this is a sub-menu for a multi-key mapping, the title for the window.
---@param prefix_key string? if this is a sub-menu, the start of tehe multi-key mapping
---@param sorter neotree.Help.Sorter?
M.show = function(state, title, prefix_key, sorter)
  local tree_width = vim.api.nvim_win_get_width(state.winid)
  local keys = get_sub_keys(state, prefix_key)

  ---@type NuiLine[]
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
  ---@type neotree.Help.Mapping[]
  local maps = {}
  for _, key in ipairs(keys) do
    maps[#maps + 1] = {
      key = key,
      mapping = state.resolved_mappings[key]
        or { text = "<error mapping for key " .. key .. ">", handler = function() end },
    }
  end

  table.sort(maps, sorter or default_help_sort)
  for _, val in ipairs(maps) do
    local nuiline = NuiLine()
    nuiline:append(
      string.format(" %14s", key_minus_prefix(val.key, prefix_key)),
      highlights.FILTER_TERM
    )
    nuiline:append(" -> ", highlights.DIM_TEXT)
    nuiline:append(val.mapping.text, highlights.NORMAL)
    local line = nuiline:content()
    if #line > max_width then
      max_width = #line
    end
    lines[#lines + 1] = nuiline
  end

  local width = math.min(60, max_width + 1)
  local col
  if state.current_position == "right" then
    col = vim.o.columns - tree_width - width - 1
  else
    col = tree_width - 1
  end

  ---@type nui_popup_options
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
    win_options = {
      foldenable = false, -- Prevent folds from hiding lines
    },
  }

  ---@return integer lines The number of screen lines that the popup should occupy at most
  local popup_max_height = function()
    -- statusline
    local statusline_lines = 0
    local laststatus = vim.o.laststatus
    if laststatus ~= 0 then
      local windows = vim.api.nvim_tabpage_list_wins(0)
      if (laststatus == 1 and #windows > 1) or laststatus > 1 then
        statusline_lines = 1
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
    return vim.o.lines - vim.o.cmdheight - statusline_lines - tab_lines - 2
  end
  local max_height = popup_max_height()
  if options.size.height > max_height then
    options.size.height = max_height
  end

  title = title or "Neotree Help"
  options = popups.popup_options(title, width, options)
  local popup = Popup(options)
  popup:mount()

  local event = require("nui.utils.autocmd").event
  popup:on({ event.VimResized }, function()
    popup:update_layout({
      size = {
        height = math.min(options.size.height --[[@as integer]], popup_max_height()),
        width = math.min(options.size.width --[[@as integer]], vim.o.columns - 2),
      },
    })
  end)
  popup:on({ event.BufLeave, event.BufDelete }, function()
    popup:unmount()
  end, { once = true })

  popup:map("n", "<esc>", function()
    popup:unmount()
  end, { noremap = true })

  for _, key in ipairs(keys) do
    -- map everything except for <escape>
    if string.match(key:lower(), "^<esc") == nil then
      local value = state.resolved_mappings[key]
        or { text = "<error mapping for key " .. key .. ">", handler = function() end }
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
