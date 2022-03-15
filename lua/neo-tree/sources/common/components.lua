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
local utils      = require("neo-tree.utils")

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
  local defined = vim.fn.sign_getdefined("DiagnosticSign" .. severity)
  if not defined then
    -- backwards compatibility...
    local old_severity = severity
    if severity == "Warning" then
      old_severity = "Warn"
    elseif severity == "Information" then
      old_severity = "Info"
    end
    defined = vim.fn.sign_getdefined("LspDiagnosticsSign" .. old_severity)
  end
  defined = defined and defined[1]
  if defined and defined.text and defined.texthl then
    return {
      text = " " .. defined.text,
      highlight = defined.texthl,
    }
  else
    return {
      text = " " .. severity:sub(1, 1),
      highlight = "Diagnostic" .. severity,
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
    if node.filtered_by and node.filtered_by.gitignored then
      git_status = "!!"
    else
      return {}
    end
  end

  local symbols = config.symbols or {}
  local change_symbol
  local change_highlt = highlights.FILE_NAME
  local status_symbol = symbols.unstaged
  local status_highlt = highlights.GIT_CONFLICT

  if git_status:sub(2, 2) == " " then
    status_symbol = symbols.staged
    status_highlt = highlights.GIT_ADDED
  end

  if git_status:match("?$") then
    status_symbol = nil
    status_highlt = highlights.GIT_UNTRACKED
    change_symbol = symbols.untracked
    change_highlt = highlights.GIT_UNTRACKED
  -- all variations of merge conflicts
  elseif git_status == "DD" then
    status_symbol = symbols.conflict
    status_highlt = highlights.GIT_CONFLICT
    change_symbol = symbols.deleted
    change_highlt = highlights.GIT_CONFLICT
  elseif git_status == "UU" then
    status_symbol = symbols.conflict
    status_highlt = highlights.GIT_CONFLICT
    change_symbol = symbols.modified
    change_highlt = highlights.GIT_CONFLICT
  elseif git_status == "AA" then
    status_symbol = symbols.conflict
    status_highlt = highlights.GIT_CONFLICT
    change_symbol = symbols.added
    change_highlt = highlights.GIT_CONFLICT
  elseif git_status:match("U") then
    status_symbol = symbols.conflict
    status_highlt = highlights.GIT_CONFLICT
    if git_status:match("A") then
      change_symbol = symbols.added
    elseif git_status:match("D") then
      change_symbol = symbols.deleted
    end
    change_highlt = highlights.GIT_CONFLICT
  -- end merge conflict section
  elseif git_status:match("M") then
    change_symbol = symbols.modified
    change_highlt = highlights.GIT_MODIFIED
  elseif git_status:match("R") then
    change_symbol = symbols.renamed
    change_highlt = highlights.GIT_RENAMED
  elseif git_status:match("[ACT]") then
    change_symbol = symbols.added
    change_highlt = highlights.GIT_ADDED
  elseif git_status:match("!") then
    status_symbol = nil
    change_symbol = symbols.ignored
    change_highlt = highlights.GIT_IGNORED
  elseif git_status:match("D") then
    change_symbol = symbols.deleted
    change_highlt = highlights.GIT_DELETED
  end

  if change_symbol or status_symbol then
    local components = {}
    if type(change_symbol) == "string" and #change_symbol > 0 then
      table.insert(components, {
        text = " " .. change_symbol,
        highlight = change_highlt,
      })
    end
    if type(status_symbol) == "string" and #status_symbol > 0 then
      table.insert(components, {
        text = " " .. status_symbol,
        highlight = status_highlt,
      })
    end
    return components
  else
    return {
      text = " [" .. git_status .. "]",
      highlight = config.highlight or change_highlt,
    }
  end

end

M.filtered_by = function(config, node, state)
  if type(node.filtered_by) == "table" then
    local fby = node.filtered_by
    if fby.name then
      return {
        text = " (hide by name)",
        highlight = highlights.HIDDEN_BY_NAME,
      }
    elseif fby.gitignored then
      return {
        text = " (gitignored)",
        highlight = highlights.GIT_IGNORED,
      }
    elseif fby.dotfiles then
      return {
        text = " (dotfile)",
        highlight = highlights.DOTFILE,
      }
    end
  end
  return {}
end

M.icon = function(config, node, state)
  local icon = config.default or " "
  local highlight = config.highlight or highlights.FILE_ICON
  if node.type == "directory" then
    highlight = highlights.DIRECTORY_ICON
    if node.loaded and not node:has_children() then
      icon = config.folder_empty or config.folder_open or "-"
    elseif node:is_expanded() then
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

  local filtered_by = M.filtered_by(config, node, state)

  return {
    text = icon .. " ",
    highlight = filtered_by.highlight or highlight,
  }
end

M.name = function(config, node, state)
  local highlight = config.highlight or highlights.FILE_NAME
  local text = node.name
  if node.type == "directory" then
    highlight = highlights.DIRECTORY_NAME
    if config.trailing_slash then
      text = text .. "/"
    end
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

  local filtered_by = M.filtered_by(config, node, state)

  return {
    text = text,
    highlight = filtered_by.highlight or highlight,
  }
end

M.indent = function(config, node, state)
  if not state.skip_marker_at_level then
    state.skip_marker_at_level = {}
  end

  local skip_marker = state.skip_marker_at_level
  local indent_size = config.indent_size or 2
  local padding = config.padding or 0
  local level = node.level
  local with_markers = config.with_markers

  if indent_size == 0 or level < 2 or not with_markers then
    return { text = string.rep(" ", indent_size * level + padding) }
  end

  local indent_marker = config.indent_marker or "│"
  local last_indent_marker = config.last_indent_marker or "└"
  local highlight = config.highlight or highlights.INDENT_MARKER

  skip_marker[level] = node.is_last_child
  local indent = {}
  if padding > 0 then
    table.insert(indent, { text = string.rep(" ", padding) })
  end

  for i = 1, level do
    local spaces_count = indent_size
    local marker = indent_marker

    if i == level and node.is_last_child then
      marker = last_indent_marker
    end

    if i > 1 and not skip_marker[i] or i == level then
      table.insert(indent, { text = marker, highlight = highlight })
      spaces_count = spaces_count - 1
    end

    table.insert(indent, { text = string.rep(" ", spaces_count) })
  end

  return indent
end

return M
