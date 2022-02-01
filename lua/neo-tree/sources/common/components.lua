-- This file contains the built-in components. Each componment is a function
-- that takes the following arguments:
--      config: A table containing the configuration provided by the user
--              when declaring this component in their renderer config.
--      node:   A NuiNode object for the currently focused node.
--      state:  The current state of the source providing the items.
--
-- The function should return either a table, or a list of tables, each of which
-- contains the following keys:
--    text:      The text to display for this item.
--    highlight: The highlight group to apply to this text.

local highlights = require("neo-tree.ui.highlights")
local utils = require("neo-tree.utils")

local M = {}

M.clipboard = function(config, node, state)
  local clipboard = state.clipboard or {}
  local clipboard_state = clipboard[node:get_id()]
  if not clipboard_state then
    return {}
  end
  return {
    text = " (" .. clipboard_state.action .. ")",
    highlight = config.highlight or highlights.DIM_TEXT,
  }
end

M.current_filter = function(config, node, state)
  local filter = node.search_pattern or ""
  if filter == "" then
    return {}
  end
  return {
    {
      text = "Find ",
      highlight = highlights.DIM_TEXT,
    },
    {
      text = string.format('"%s"', filter),
      highlight = config.highlight or highlights.FILTER_TERM,
    },
    {
      text = " in ",
      highlight = highlights.DIM_TEXT,
    },
  }
end

M.diagnostics = function(config, node, state)
  local diag = state.diagnostics_lookup or {}
  local diag_state = diag[node:get_id()]
  if not diag_state then
    return {}
  end
  if config.errors_only and diag_state.severity_number > 1 then
    return {}
  end
  local severity = diag_state.severity_string
  local defined = vim.fn.sign_getdefined("LspDiagnosticsSign" .. severity)
  defined = defined and defined[1]
  if defined and defined.text and defined.texthl then
    return {
      text = " " .. defined.text,
      highlight = defined.texthl,
    }
  else
    return {
      text = " " .. severity:sub(1, 1),
      highlight = "LspDiagnosticsDefault" .. severity,
    }
  end
end

M.git_status = function(config, node, state)
  local git_status_lookup = state.git_status_lookup
  if not git_status_lookup then
    return {}
  end
  local git_status = git_status_lookup[node.path]
  if not git_status then
    return {}
  end

  local highlight = highlights.FILE_NAME
  if git_status:match("?$") then
    highlight = highlights.GIT_UNTRACKED
  elseif git_status:match("U") then
    highlight = highlights.GIT_CONFLICT
  elseif git_status == "AA" then
    highlight = highlights.GIT_CONFLICT
  elseif git_status:match("M") then
    highlight = highlights.GIT_MODIFIED
  elseif git_status:match("[ACRT]") then
    highlight = highlights.GIT_ADDED
  end

  return {
    text = " [" .. git_status .. "]",
    highlight = config.highlight or highlight,
  }
end

M.icon = function(config, node, state)
  local icon = config.default or " "
  local padding = config.padding or " "
  local highlight = config.highlight or highlights.FILE_ICON
  if node.type == "directory" then
    highlight = highlights.DIRECTORY_ICON
    if node:is_expanded() then
      icon = config.folder_open or "-"
    else
      icon = config.folder_closed or "+"
    end
  elseif node.type == "file" then
    local success, web_devicons = pcall(require, "nvim-web-devicons")
    if success then
      local devicon, hl = web_devicons.get_icon(node.name, node.ext)
      icon = devicon or icon
      highlight = hl or highlight
    end
  end
  return {
    text = icon .. padding,
    highlight = highlight,
  }
end

M.name = function(config, node, state)
  local highlight = config.highlight or highlights.FILE_NAME
  if node.type == "directory" then
    highlight = highlights.DIRECTORY_NAME
  end
  if node:get_depth() == 1 then
    highlight = highlights.ROOT_NAME
  else
    if config.use_git_status_colors == nil or config.use_git_status_colors then
      local git_status = state.components.git_status({}, node, state)
      if git_status and git_status.highlight then
        highlight = git_status.highlight
      end
    end
  end
  return {
    text = node.name,
    highlight = highlight,
  }
end

local indent_cache = {}

local indent_without_markers = function(config, node, state)
  local level = node.level
  local indent_size = state.indent_size or 2

  if level == 0 or indent_size == 0 then
    return {}
  end

  if not indent_cache[level] then
    local indent = utils.table_copy(indent_cache[level - 1] or {})

    local spaces = utils.make_spaces(indent_size)
    table.insert(indent, { text = spaces })

    indent_cache[level] = indent
  end

  local node_indent = utils.table_copy(indent_cache[level])
  -- table.insert(node_indent, { text = " " })

  return node_indent
end

local prevent_indent = {}

M.indent = function(config, node, state)
  local indent_size = state.indent_size or 2
  if indent_size == 0 then
    return {}
  end

  local level = node.level
  local with_markers = config.with_markers

  if level < 2 or not with_markers then
    return indent_without_markers(config, node, state)
  end

  local indent_marker = config.indent_marker or "│"
  local last_indent_marker = config.last_indent_marker or "└"
  local highlight = config.highlight or highlights.INDENT_MARKER

  prevent_indent[level] = node.is_last_child
  local indent = {}

  for i = 1, level do
    local spaces_count = indent_size
    local marker = indent_marker

    if i == level and node.is_last_child then
      marker = last_indent_marker
    end

    if i > 1 and not prevent_indent[i] or i == level then
      table.insert(indent, { text = marker, highlight = highlight })
      spaces_count = spaces_count - 1
    end

    local spaces = utils.make_spaces(spaces_count)
    table.insert(indent, { text = spaces })
  end

  return indent
end

return M
