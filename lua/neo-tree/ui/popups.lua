local NuiText = require("nui.text")
local NuiPopup = require("nui.popup")
local nt = require("neo-tree")
local highlights = require("neo-tree.ui.highlights")
local log = require("neo-tree.log")

local M = {}

local winborder_option_exists = vim.fn.exists("&winborder") > 0
-- These borders will cause errors when trying to display border text with them
local invalid_borders = { "", "none", "shadow" }
---@param title string
---@param min_width integer?
---@param override_options table?
M.popup_options = function(title, min_width, override_options)
  if string.len(title) ~= 0 then
    title = " " .. title .. " "
  end
  min_width = min_width or 30
  local width = string.len(title) + 2

  local popup_border_style = nt.config.popup_border_style
  if popup_border_style == "" then
    -- Try to use winborder
    if not winborder_option_exists or vim.tbl_contains(invalid_borders, vim.o.winborder) then
      popup_border_style = "single"
    else
      ---@diagnostic disable-next-line: cast-local-type
      popup_border_style = vim.o.winborder
    end
  end
  local popup_border_text = NuiText(title, highlights.FLOAT_TITLE)
  local col = 0
  -- fix popup position when using multigrid
  local popup_last_col = vim.api.nvim_win_get_position(0)[2] + width + 2
  if popup_last_col >= vim.o.columns then
    col = vim.o.columns - popup_last_col
  end
  ---@type nui_popup_options
  local popup_options = {
    ns_id = highlights.ns_id,
    relative = "cursor",
    position = {
      row = 1,
      col = col,
    },
    size = width,
    border = {
      text = {
        top = popup_border_text,
      },
      ---@diagnostic disable-next-line: assign-type-mismatch
      style = popup_border_style,
      highlight = highlights.FLOAT_BORDER,
    },
    win_options = {
      winhighlight = "Normal:"
        .. highlights.FLOAT_NORMAL
        .. ",FloatBorder:"
        .. highlights.FLOAT_BORDER,
    },
    buf_options = {
      bufhidden = "delete",
      buflisted = false,
      filetype = "neo-tree-popup",
    },
  }

  if popup_border_style == "NC" then
    local blank = NuiText(" ", highlights.TITLE_BAR)
    popup_border_text = NuiText(title, highlights.TITLE_BAR)
    popup_options.border = {
      style = { "▕", blank, "▏", "▏", " ", "▔", " ", "▕" },
      highlight = highlights.FLOAT_BORDER,
      text = {
        top = popup_border_text,
        top_align = "left",
      },
    }
  end

  if override_options then
    return vim.tbl_extend("force", popup_options, override_options)
  else
    return popup_options
  end
end

---@param title string
---@param message elem_or_list<string|integer>
---@param size integer?
M.alert = function(title, message, size)
  local lines = {}
  local max_line_width = title:len()
  ---@param line any
  local add_line = function(line)
    line = tostring(line)
    if line:len() > max_line_width then
      max_line_width = line:len()
    end
    table.insert(lines, line)
  end

  if type(message) == "table" then
    for _, v in ipairs(message) do
      add_line(v)
    end
  else
    add_line(message)
  end

  add_line("")
  add_line(" Press <Escape> or <Enter> to close")

  local win_options = M.popup_options(title, 80)
  win_options.zindex = 60
  win_options.size = {
    width = max_line_width + 4,
    height = #lines + 1,
  }
  local win = NuiPopup(win_options)
  win:mount()

  local success, msg = pcall(vim.api.nvim_buf_set_lines, win.bufnr, 0, 0, false, lines)
  if success then
    win:map("n", "<esc>", function()
      win:unmount()
    end, { noremap = true })

    win:map("n", "<enter>", function()
      win:unmount()
    end, { noremap = true })

    local event = require("nui.utils.autocmd").event
    win:on({ event.BufLeave, event.BufDelete }, function()
      win:unmount()
    end, { once = true })

    -- why is this necessary?
    vim.api.nvim_set_current_win(win.winid)
  else
    log.error(msg)
    win:unmount()
  end
end

return M
