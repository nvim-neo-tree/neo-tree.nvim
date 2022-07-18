local vim = vim
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")

local M = {}

local get_separator_tbl = function(sep)
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
  local sep = get_separator_tbl(config.source_selector.separator)
  if is_active then
    sep =
      vim.tbl_deep_extend("force", sep, get_separator_tbl(config.source_selector.separator_active))
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
  local separator_config =
    utils.resolve_config_option(require("neo-tree").config, "source_selector", {})
  if separator_config == nil then
    log.warn("Cannot find source_selector config. `create_selector` abort.")
    return {}
  end
  local text = separator_config.tab_labels[source_name] or source_name
  local tab_hl = is_active and separator_config.highlight_tab_active
    or separator_config.highlight_tab
  local sep_hl = is_active and separator_config.highlight_separator_active
    or separator_config.highlight_separator
  local get_strlen = vim.fn.strdisplaywidth
  return {
    index = source_index,
    is_active = is_active,
    left = separator.left,
    right = separator.right,
    text = text,
    tab_hl = tab_hl,
    sep_hl = sep_hl,
    length = get_strlen(text) + get_strlen(separator.left) + get_strlen(separator.right),
    text_length = get_strlen(text),
  }
end

local text_with_hl = function(text, tab_hl)
  return string.format("%%#%s#%s", tab_hl, text)
end

local add_padding = function(padding_legth, padchar)
  if padchar == nil then
    padchar = " "
  end
  return string.rep(padchar, math.floor(padding_legth))
end

M.text_layout = function(text, content_layout, output_width, text_length)
  if text_length == nil then
    text_length = vim.fn.strdisplaywidth(text)
  end
  local pad_length = output_width - text_length
  if pad_length < 0 then
    return string.sub(text, 1, vim.str_byteindex(text, output_width)) -- lua string sub with multibyte seq
  elseif content_layout == "start" then
    return text .. add_padding(pad_length)
  elseif content_layout == "end" then
    return add_padding(pad_length) .. text
  elseif content_layout == "center" then
    return add_padding(pad_length / 2) .. text .. add_padding(math.ceil(pad_length / 2))
  else
    return text
  end
end

M.render_tab = function(left_sep, right_sep, sep_hl, text, tab_hl, source_index)
  local res = "%" .. source_index .. "@v:lua.___neotree_selector_click@"
  if left_sep ~= nil then
    res = res .. text_with_hl(left_sep, sep_hl)
  end
  res = res .. text_with_hl(text, tab_hl)
  if right_sep ~= nil then
    res = res .. text_with_hl(right_sep, sep_hl)
  end
  return res
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
  local remaining_width = width - length_separators
  local return_string = add_padding(padding.left)
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
          tab.index
        )
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
          tab.index
        )
    end
  else -- config.source_selector.tab_labels == "start", "end", "center"
    local tmp = ""
    for _, tab in ipairs(tabs) do
      tmp = tmp .. M.render_tab(tab.left, tab.right, tab.sep_hl, tab.text, tab.tab_hl, tab.index)
    end
    return_string = return_string .. M.text_layout(tmp, tabs_layout, width, length_sum)
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

-- @v:lua@ in the tabline only supports global functions, so this is
-- the only way to add click handlers without autoloaded vimscript functions
_G.___neotree_selector_click = function(id, _, _, _)
  local sources = require("neo-tree").config.sources
  if id < 1 or id > #sources then
    return
  end
  require("neo-tree.command").execute({
    source = sources[id],
    position = "current",
  })
end

return M
