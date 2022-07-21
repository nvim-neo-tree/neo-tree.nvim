local vim = vim
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")

local M = {}

local sep_tbl = function(sep)
  if type(sep) == "nil" then
    return {}
  elseif type(sep) ~= "table" then
    return { left = sep, right = sep, override = "active" }
  end
  return sep
end

local get_separators = function(source_index, active_index, force_ignore_left, force_ignore_right)
  local config = require("neo-tree").config
  local is_active = source_index == active_index
  local sep = sep_tbl(config.source_selector.separator)
  if is_active then
    sep = vim.tbl_deep_extend("force", sep, sep_tbl(config.source_selector.separator_active))
  end
  local show_left = sep.override == "left"
    or (sep.override == "active" and source_index <= active_index)
    or sep.override == nil
  local show_right = sep.override == "right"
    or (sep.override == "active" and source_index >= active_index)
    or sep.override == nil
  return {
    left = (show_left and not force_ignore_left) and sep.left or "",
    right = (show_right and not force_ignore_right) and sep.right or "",
  }
end

M.get_selector_tab_info = function(source_name, source_index, is_active, separator)
  local config = require("neo-tree").config
  local separator_config = utils.resolve_config_option(config, "source_selector", nil)
  if separator_config == nil then
    log.warn("Cannot find source_selector config. `create_selector` abort.")
    return {}
  end
  local get_strlen = vim.api.nvim_strwidth
  local text = separator_config.tab_labels[source_name] or source_name
  local text_length = get_strlen(text)
  if separator_config.tabs_min_width ~= nil and text_length < separator_config.tabs_min_width then
    text = M.text_layout(text, separator_config.content_layout, separator_config.tabs_min_width)
    text_length = separator_config.tabs_min_width
  end
  if separator_config.tabs_max_width ~= nil and text_length > separator_config.tabs_max_width then
    text = M.text_layout(text, separator_config.content_layout, separator_config.tabs_max_width)
    text_length = separator_config.tabs_max_width
  end
  local tab_hl = is_active and separator_config.highlight_tab_active
    or separator_config.highlight_tab
  local sep_hl = is_active and separator_config.highlight_separator_active
    or separator_config.highlight_separator
  return {
    index = source_index,
    is_active = is_active,
    left = separator.left,
    right = separator.right,
    text = text,
    tab_hl = tab_hl,
    sep_hl = sep_hl,
    length = text_length + get_strlen(separator.left) + get_strlen(separator.right),
    text_length = text_length,
  }
end

local text_with_hl = function(text, tab_hl)
  if tab_hl == nil then
    return text
  end
  return string.format("%%#%s#%s", tab_hl, text)
end

local add_padding = function(padding_legth, hl_padding, padchar)
  if padchar == nil then
    padchar = " "
  end
  return text_with_hl(string.rep(padchar, math.floor(padding_legth)), hl_padding)
end

M.text_layout = function(text, content_layout, output_width, text_length, hl_padding)
  if text_length == nil then
    text_length = vim.fn.strdisplaywidth(text)
  end
  local pad_length = output_width - text_length
  local left_pad, right_pad = 0, 0
  if pad_length < 0 then
    return string.sub(text, 1, vim.str_byteindex(text, output_width)) -- lua string sub with multibyte seq
  elseif content_layout == "start" then
    left_pad, right_pad = 0, pad_length
  elseif content_layout == "end" then
    left_pad, right_pad = pad_length, 0
  elseif content_layout == "center" then
    left_pad, right_pad = pad_length / 2, math.ceil(pad_length / 2)
  end
  return add_padding(left_pad, hl_padding) .. text .. add_padding(right_pad, hl_padding)
end

M.render_tab = function(left_sep, right_sep, sep_hl, text, tab_hl, click_id)
  local res = "%" .. click_id .. "@v:lua.___neotree_selector_click@"
  if left_sep ~= nil then
    res = res .. text_with_hl(left_sep, sep_hl)
  end
  res = res .. text_with_hl(text, tab_hl)
  if right_sep ~= nil then
    res = res .. text_with_hl(right_sep, sep_hl)
  end
  return res
end

M.get = function()
  local state = require("neo-tree.sources.manager").get_state_for_active_window()
  if state == nil then
    return
  else
    return M.create_selector(state, vim.api.nvim_win_get_width(0))
  end
end

M.create_selector = function(state, width)
  local config = require("neo-tree").config
  if config == nil then
    log.warn("Cannot find config. `create_selector` abort.")
    return nil
  end

  -- load padding from config
  local padding = config.source_selector.padding
  if type(padding) == "number" then
    padding = { left = padding, right = padding }
  end
  width = width - padding.left - padding.right

  -- generate information of each tab (look `M.get_selector_tab_info` for type hint)
  local tabs = {}
  local active_index = #config.sources
  local length_sum, length_active, length_separators = 0, 0, 0
  for i, source_name in ipairs(config.sources) do
    local is_active = source_name == state.name
    if is_active then
      active_index = i
    end
    local separator = get_separators(
      i,
      active_index,
      config.source_selector.show_separator_on_edge == false and i == 1,
      config.source_selector.show_separator_on_edge == false and i == #config.sources
    )
    local element = M.get_selector_tab_info(source_name, i, is_active, separator)
    length_sum = length_sum + element.length
    length_separators = length_separators + element.length - element.text_length
    if is_active then
      length_active = element.length
    end
    table.insert(tabs, element)
  end

  -- start creating string to display
  local tabs_layout = config.source_selector.tabs_layout
  local content_layout = config.source_selector.content_layout or "center"
  local hl_background = config.source_selector.highlight_background
  local remaining_width = width - length_separators
  local return_string = text_with_hl(add_padding(padding.left), hl_background)
  if width < length_sum and config.source_selector.text_trunc_to_fit then -- not enough width
    local each_width = math.floor(remaining_width / #tabs)
    local remaining = remaining_width % each_width
    tabs_layout = "start"
    length_sum = width
    for _, tab in ipairs(tabs) do
      tab.text = M.text_layout( -- truncate text and pass it to "start"
        tab.text,
        "center",
        each_width + (tab.is_active and remaining or 0)
      )
    end
  end
  if tabs_layout == "active" then
    local active_tab_length = width - length_sum + length_active
    for _, tab in ipairs(tabs) do
      return_string = return_string
        .. M.render_tab(
          tab.left,
          tab.right,
          tab.sep_hl,
          M.text_layout(tab.text, tab.is_active and content_layout or nil, active_tab_length),
          tab.tab_hl,
          M.calc_click_id_from_source(state.winid or 0, tab.index)
        )
        .. text_with_hl("", hl_background)
    end
  elseif tabs_layout == "equal" then
    for _, tab in ipairs(tabs) do
      return_string = return_string
        .. M.render_tab(
          tab.left,
          tab.right,
          tab.sep_hl,
          M.text_layout(tab.text, content_layout, math.floor(remaining_width / #tabs)),
          tab.tab_hl,
          M.calc_click_id_from_source(state.winid or 0, tab.index)
        )
        .. text_with_hl("", hl_background)
    end
  else -- config.source_selector.tab_labels == "start", "end", "center"
    local tmp = ""
    for _, tab in ipairs(tabs) do
      tmp = tmp
        .. M.render_tab(
          tab.left,
          tab.right,
          tab.sep_hl,
          tab.text,
          tab.tab_hl,
          M.calc_click_id_from_source(state.winid or 0, tab.index)
        )
    end
    return_string = return_string
      .. M.text_layout(tmp, tabs_layout, width, length_sum, hl_background)
  end
  return return_string .. "%0@v:lua.___neotree_selector_click@"
end

M.append_source_selector = function(win_options, state, size)
  local sel_config = utils.resolve_config_option(require("neo-tree").config, "source_selector", {})
  if sel_config and sel_config.winbar then
    win_options.winbar = M.create_selector(state, size)
  end
  if sel_config and sel_config.statusline then
    win_options.statusline = M.create_selector(state, size)
  end
end

M.set_source_selector = function(state, size)
  local sel_config = utils.resolve_config_option(require("neo-tree").config, "source_selector", {})
  if sel_config and sel_config.winbar then
    vim.wo[state.winid].winbar = M.create_selector(state, size)
  end
  if sel_config and sel_config.statusline then
    vim.wo[state.winid].statusline = M.create_selector(state, size)
  end
end

M.auto_set_source_selector = function(state)
  local sel_config = utils.resolve_config_option(require("neo-tree").config, "source_selector", {})
  local win_width = vim.api.nvim_win_get_width(state.winid)
  if sel_config and sel_config.winbar then
    vim.wo[state.winid].winbar = "%{%v:lua.require'neo-tree.ui.selector'.get()%}"
  end
  if sel_config and sel_config.statusline then
    vim.wo[state.winid].statusline = "%{%v:lua.require'neo-tree.ui.selector'.get()%}"
  end
end

M.return_source_selector = function(state)
  local win_width = vim.api.nvim_win_get_width(state.winid)
  return M.create_selector(state, win_width)
end

M.calc_click_id_from_source = function(winid, source_index)
  local base_number = #require("neo-tree").config.sources + 1
  return base_number * winid + source_index
end

M.calc_source_from_click_id = function(click_id)
  local base_number = #require("neo-tree").config.sources + 1
  return math.floor(click_id / base_number), click_id % base_number
end

-- @v:lua@ in the tabline only supports global functions, so this is
-- the only way to add click handlers without autoloaded vimscript functions
_G.___neotree_selector_click = function(id, _, _, _)
  local sources = require("neo-tree").config.sources
  if id < 1 then
    return
  end
  local current_win = vim.api.nvim_get_current_win()
  local winid, source_index = M.calc_source_from_click_id(id)
  vim.api.nvim_set_current_win(winid)
  require("neo-tree.command").execute({
    source = sources[source_index],
    position = "current",
  })
  if current_win ~= winid then
    vim.api.nvim_set_current_win(current_win)
  end
end

return M
