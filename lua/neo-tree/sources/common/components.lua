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
local file_nesting = require("neo-tree.sources.common.file-nesting")
local container = require("neo-tree.sources.common.container")
local nt = require("neo-tree")

---@alias neotree.Component.Common._Key
---|"bufnr"
---|"clipboard"
---|"container"
---|"current_filter"
---|"diagnostics"
---|"git_status"
---|"filtered_by"
---|"icon"
---|"modified"
---|"name"
---|"indent"
---|"file_size"
---|"last_modified"
---|"created"
---|"symlink_target"
---|"type"

---@class neotree.Component.Common Use the neotree.Component.Common.* types to get more specific types.
---@field [1] neotree.Component.Common._Key

---@type table<neotree.Component.Common._Key, neotree.FileRenderer>
local M = {}

local make_two_char = function(symbol)
  if vim.fn.strchars(symbol) == 1 then
    return symbol .. " "
  else
    return symbol
  end
end

---@class (exact) neotree.Component.Common.Bufnr : neotree.Component
---@field [1] "bufnr"?

-- Config fields below:
-- only works in the buffers component, but it's here so we don't have to defined
-- multple renderers.
---@param config neotree.Component.Common.Bufnr
M.bufnr = function(config, node, _)
  local highlight = config.highlight or highlights.BUFFER_NUMBER
  local bufnr = node.extra and node.extra.bufnr
  if not bufnr then
    return {}
  end
  return {
    text = string.format("#%s", bufnr),
    highlight = highlight,
  }
end

---@class (exact) neotree.Component.Common.Clipboard : neotree.Component
---@field [1] "clipboard"?

---@param config neotree.Component.Common.Clipboard
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

---@class (exact) neotree.Component.Common.Container : neotree.Component
---@field [1] "container"?
---@field left_padding integer?
---@field right_padding integer?
---@field enable_character_fade boolean?
---@field content (neotree.Component|{zindex: number, align: "left"|"right"|nil})[]?

M.container = container.render

---@class (exact) neotree.Component.Common.CurrentFilter : neotree.Component
---@field [1] "current_filter"

---@param config neotree.Component.Common.CurrentFilter
M.current_filter = function(config, node, _)
  local filter = node.search_pattern or ""
  if filter == "" then
    return {}
  end
  return {
    {
      text = "Find",
      highlight = highlights.DIM_TEXT,
    },
    {
      text = string.format('"%s"', filter),
      highlight = config.highlight or highlights.FILTER_TERM,
    },
    {
      text = "in",
      highlight = highlights.DIM_TEXT,
    },
  }
end

---`sign_getdefined` based wrapper with compatibility
---@param severity string
---@return vim.fn.sign_getdefined.ret.item
local get_legacy_sign = function(severity)
  local sign = vim.fn.sign_getdefined("DiagnosticSign" .. severity)
  if vim.tbl_isempty(sign) then
    -- backwards compatibility...
    local old_severity = severity
    if severity == "Warning" then
      old_severity = "Warn"
    elseif severity == "Information" then
      old_severity = "Info"
    end
    sign = vim.fn.sign_getdefined("LspDiagnosticsSign" .. old_severity)
  end
  return sign and sign[1]
end

local nvim_0_10 = vim.fn.has("nvim-0.10") > 0
---Returns the sign corresponding to the given severity
---@param severity string
---@return vim.fn.sign_getdefined.ret.item
local function get_diagnostic_sign(severity)
  local sign

  if nvim_0_10 then
    local signs = vim.diagnostic.config().signs

    if type(signs) == "function" then
      --TODO: Find a better way to get a namespace
      local namespaces = vim.diagnostic.get_namespaces()
      if not vim.tbl_isempty(namespaces) then
        local ns_id = next(namespaces)
        ---@cast ns_id -nil
        signs = signs(ns_id, 0)
      end
    end

    if type(signs) == "table" then
      local identifier = severity:sub(1, 1)
      if identifier == "H" then
        identifier = "N"
      end
      sign = {
        text = (signs.text or {})[vim.diagnostic.severity[identifier]],
        texthl = "DiagnosticSign" .. severity,
      }
    elseif signs == true then
      sign = get_legacy_sign(severity)
    end
  else -- before 0.10
    sign = get_legacy_sign(severity)
  end

  if type(sign) ~= "table" then
    sign = {}
  end
  return sign
end

---@class (exact) neotree.Component.Common.Diagnostics : neotree.Component
---@field [1] "diagnostics"?
---@field errors_only boolean?
---@field hide_when_expanded boolean?
---@field symbols table<string, string>?
---@field highlights table<string, string>?

---@param config neotree.Component.Common.Diagnostics
M.diagnostics = function(config, node, state)
  local diag = state.diagnostics_lookup or {}
  local diag_state = utils.index_by_path(diag, node:get_id())
  if config.hide_when_expanded and node.type == "directory" and node:is_expanded() then
    return {}
  end
  if not diag_state then
    return {}
  end
  if config.errors_only and diag_state.severity_number > 1 then
    return {}
  end
  ---@type string
  local severity = diag_state.severity_string
  local sign = get_diagnostic_sign(severity)

  -- check for overrides in the component config
  local severity_lower = severity:lower()
  if config.symbols and config.symbols[severity_lower] then
    sign.texthl = sign.texthl or ("Diagnostic" .. severity)
    sign.text = config.symbols[severity_lower]
  end
  if config.highlights and config.highlights[severity_lower] then
    sign.text = sign.text or severity:sub(1, 1)
    sign.texthl = config.highlights[severity_lower]
  end

  if sign.text and sign.texthl then
    return {
      text = make_two_char(sign.text),
      highlight = sign.texthl,
    }
  else
    return {
      text = severity:sub(1, 1),
      highlight = "Diagnostic" .. severity,
    }
  end
end

---@class (exact) neotree.Component.Common.GitStatus : neotree.Component
---@field [1] "git_status"?
---@field hide_when_expanded boolean?
---@field symbols table<string, string>?

---@param config neotree.Component.Common.GitStatus
M.git_status = function(config, node, state)
  local git_status_lookup = state.git_status_lookup
  if config.hide_when_expanded and node.type == "directory" and node:is_expanded() then
    return {}
  end
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
  ---@type string?
  local status_symbol = symbols.staged
  local status_highlt = highlights.GIT_STAGED
  if node.type == "directory" and git_status:len() == 1 then
    status_symbol = nil
  end

  if git_status:sub(1, 1) == " " then
    status_symbol = symbols.unstaged
    status_highlt = highlights.GIT_UNSTAGED
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
        text = make_two_char(change_symbol),
        highlight = change_highlt,
      })
    end
    if type(status_symbol) == "string" and #status_symbol > 0 then
      table.insert(components, {
        text = make_two_char(status_symbol),
        highlight = status_highlt,
      })
    end
    return components
  else
    return {
      text = "[" .. git_status .. "]",
      highlight = config.highlight or change_highlt,
    }
  end
end

---@class neotree.Component.Common.FilteredBy
---@field [1] "filtered_by"?
M.filtered_by = function(_, node, state)
  local fby = node.filtered_by
  if not state.filtered_items or type(fby) ~= "table" then
    return {}
  end
  repeat
    if fby.name then
      return {
        text = "(hide by name)",
        highlight = highlights.HIDDEN_BY_NAME,
      }
    elseif fby.pattern then
      return {
        text = "(hide by pattern)",
        highlight = highlights.HIDDEN_BY_NAME,
      }
    elseif fby.gitignored then
      return {
        text = "(gitignored)",
        highlight = highlights.GIT_IGNORED,
      }
    elseif fby.dotfiles then
      return {
        text = "(dotfile)",
        highlight = highlights.DOTFILE,
      }
    elseif fby.hidden then
      return {
        text = "(hidden)",
        highlight = highlights.WINDOWS_HIDDEN,
      }
    end
    fby = fby.parent
  until not state.filtered_items.children_inherit_highlights or not fby
  return {}
end

---@class (exact) neotree.Component.Common.Icon : neotree.Component
---@field [1] "icon"?
---@field default string The default icon for a node.
---@field folder_empty string The string to display to represent an empty folder.
---@field folder_empty_open string The icon to display to represent an empty but open folder.
---@field folder_open string The icon to display for an open folder.
---@field folder_closed string The icon to display for a closed folder.
---@field provider neotree.IconProvider?

---@param config neotree.Component.Common.Icon
M.icon = function(config, node, state)
  -- calculate default icon
  ---@type neotree.Render.Node
  local icon =
    { text = config.default or " ", highlight = config.highlight or highlights.FILE_ICON }
  if node.type == "directory" then
    icon.highlight = highlights.DIRECTORY_ICON
    if node.loaded and not node:has_children() then
      icon.text = not node.empty_expanded and config.folder_empty or config.folder_empty_open
    elseif node:is_expanded() then
      icon.text = config.folder_open or "-"
    else
      icon.text = config.folder_closed or "+"
    end
  end

  -- use icon provider if available
  if config.provider then
    icon = config.provider(icon, node, state) or icon
  end

  local filtered_by = M.filtered_by(config, node, state)

  icon.text = icon.text .. " " -- add padding
  icon.highlight = filtered_by.highlight or icon.highlight --  prioritize filtered highlighting

  return icon
end

---@class (exact) neotree.Component.Common.Modified : neotree.Component
---@field [1] "modified"?
---@field symbol string?

---@param config neotree.Component.Common.Modified
M.modified = function(config, node, state)
  local opened_buffers = state.opened_buffers or {}
  local buf_info = utils.index_by_path(opened_buffers, node.path)

  if buf_info and buf_info.modified then
    return {
      text = (make_two_char(config.symbol) or "[+]"),
      highlight = config.highlight or highlights.MODIFIED,
    }
  else
    return {}
  end
end

---@class (exact) neotree.Component.Common.Name : neotree.Component
---@field [1] "name"?
---@field trailing_slash boolean?
---@field use_git_status_colors boolean?
---@field highlight_opened_files boolean|"all"?
---@field right_padding integer?

---@param config neotree.Component.Common.Name
M.name = function(config, node, state)
  local highlight = config.highlight or highlights.FILE_NAME
  local text = node.name
  if node.type == "directory" then
    highlight = highlights.DIRECTORY_NAME
    if config.trailing_slash and text ~= "/" then
      text = text .. "/"
    end
  end

  if node:get_depth() == 1 and node.type ~= "message" then
    highlight = highlights.ROOT_NAME
    if state.current_position == "current" and state.sort and state.sort.label == "Name" then
      local icon = state.sort.direction == 1 and "▲" or "▼"
      text = text .. "  " .. icon
    end
  else
    local filtered_by = M.filtered_by(config, node, state)
    highlight = filtered_by.highlight or highlight
    if config.use_git_status_colors then
      local git_status = state.components.git_status({}, node, state)
      if git_status and git_status.highlight then
        highlight = git_status.highlight
      end
    end
  end

  local hl_opened = config.highlight_opened_files
  if hl_opened then
    local opened_buffers = state.opened_buffers or {}
    if
      (hl_opened == "all" and opened_buffers[node.path])
      or (opened_buffers[node.path] and opened_buffers[node.path].loaded)
    then
      highlight = highlights.FILE_NAME_OPENED
    end
  end

  if type(config.right_padding) == "number" then
    if config.right_padding > 0 then
      text = text .. string.rep(" ", config.right_padding)
    end
  else
    text = text
  end

  return {
    text = text,
    highlight = highlight,
  }
end

---@class (exact) neotree.Component.Common.Indent : neotree.Component
---@field [1] "indent"?
---@field expander_collapsed string?
---@field expander_expanded string?
---@field expander_highlight string?
---@field indent_marker string?
---@field indent_size integer?
---@field last_indent_marker string?
---@field padding integer?
---@field with_expanders boolean?
---@field with_markers boolean?

---@param config neotree.Component.Common.Indent
M.indent = function(config, node, state)
  if not state.skip_marker_at_level then
    state.skip_marker_at_level = {}
  end

  local strlen = vim.fn.strdisplaywidth
  local skip_marker = state.skip_marker_at_level
  ---@cast skip_marker -nil
  local indent_size = config.indent_size or 2
  local padding = config.padding or 0
  local level = node.level
  local with_markers = config.with_markers
  local with_expanders = config.with_expanders == nil and file_nesting.is_enabled()
    or config.with_expanders
  local marker_highlight = config.highlight or highlights.INDENT_MARKER
  local expander_highlight = config.expander_highlight or config.highlight or highlights.EXPANDER

  local function get_expander()
    if with_expanders and utils.is_expandable(node) then
      return node:is_expanded() and (config.expander_expanded or "")
        or (config.expander_collapsed or "")
    end
  end

  if indent_size == 0 or level < 2 or not with_markers then
    local len = indent_size * level + padding
    local expander = get_expander()
    if level == 0 or not expander then
      return {
        text = string.rep(" ", len),
      }
    end
    return {
      text = string.rep(" ", len - strlen(expander) - 1) .. expander .. " ",
      highlight = expander_highlight,
    }
  end

  local indent_marker = config.indent_marker or "│"
  local last_indent_marker = config.last_indent_marker or "└"

  skip_marker[level] = node.is_last_child
  local indent = {}
  if padding > 0 then
    table.insert(indent, { text = string.rep(" ", padding) })
  end

  for i = 1, level do
    local char = ""
    local spaces_count = indent_size
    local highlight = nil

    if i > 1 and not skip_marker[i] or i == level then
      spaces_count = spaces_count - 1
      char = indent_marker
      highlight = marker_highlight
      if i == level then
        local expander = get_expander()
        if expander then
          char = expander
          highlight = expander_highlight
        elseif node.is_last_child then
          char = last_indent_marker
          spaces_count = spaces_count - (vim.api.nvim_strwidth(last_indent_marker) - 1)
        end
      end
    end

    table.insert(indent, {
      text = char .. string.rep(" ", spaces_count),
      highlight = highlight,
      no_next_padding = true,
    })
  end

  return indent
end

local truncate_string = function(str, max_length)
  if #str <= max_length then
    return str
  end
  return str:sub(1, max_length - 1) .. "…"
end

local get_header = function(state, label, size)
  if state.sort and state.sort.label == label then
    local icon = state.sort.direction == 1 and "▲" or "▼"
    size = size - 2
    ---diagnostic here is wrong, printf has arbitrary args.
    ---@diagnostic disable-next-line: redundant-parameter
    return vim.fn.printf("%" .. size .. "s %s  ", truncate_string(label, size), icon)
  end
  return vim.fn.printf("%" .. size .. "s  ", truncate_string(label, size))
end

---@class (exact) neotree.Component.Common.FileSize : neotree.Component
---@field [1] "file_size"?
---@field width integer?

---@param config neotree.Component.Common.FileSize
M.file_size = function(config, node, state)
  -- Root node gets column labels
  if node:get_depth() == 1 then
    return {
      text = get_header(state, "Size", config.width),
      highlight = highlights.FILE_STATS_HEADER,
    }
  end

  local text = "-"
  if node.type == "file" then
    local stat = utils.get_stat(node)
    local size = stat and stat.size or nil
    if size then
      local success, human = pcall(utils.human_size, size)
      if success then
        text = human or text
      end
    end
  end

  return {
    text = vim.fn.printf("%" .. config.width .. "s  ", truncate_string(text, config.width)),
    highlight = config.highlight or highlights.FILE_STATS,
  }
end

---@class (exact) neotree.Component.Common._Time : neotree.Component
---@field format neotree.DateFormat
---@field width integer?

---@param config neotree.Component.Common._Time
local file_time = function(config, node, state, stat_field)
  -- Root node gets column labels
  if node:get_depth() == 1 then
    local label = stat_field
    if stat_field == "mtime" then
      label = "Last Modified"
    elseif stat_field == "birthtime" then
      label = "Created"
    end
    return {
      text = get_header(state, label, config.width),
      highlight = highlights.FILE_STATS_HEADER,
    }
  end

  local stat = utils.get_stat(node)
  local value = stat and stat[stat_field]
  local seconds = value and value.sec or nil
  local display = seconds and utils.date(config.format, seconds) or "-"

  return {
    text = vim.fn.printf("%" .. config.width .. "s  ", truncate_string(display, config.width)),
    highlight = config.highlight or highlights.FILE_STATS,
  }
end

---@class (exact) neotree.Component.Common.LastModified : neotree.Component.Common._Time
---@field [1] "last_modified"?

---@param config neotree.Component.Common.LastModified
M.last_modified = function(config, node, state)
  return file_time(config, node, state, "mtime")
end

---@class (exact) neotree.Component.Common.Created : neotree.Component.Common._Time
---@field [1] "created"?

---@param config neotree.Component.Common.Created
M.created = function(config, node, state)
  return file_time(config, node, state, "birthtime")
end

---@class (exact) neotree.Component.Common.SymlinkTarget : neotree.Component
---@field [1] "symlink_target"?
---@field text_format string?

---@param config neotree.Component.Common.SymlinkTarget
M.symlink_target = function(config, node, _)
  if node.is_link then
    return {
      text = string.format(config.text_format or "-> %s", node.link_to),
      highlight = config.highlight or highlights.SYMBOLIC_LINK_TARGET,
    }
  else
    return {}
  end
end

---@class (exact) neotree.Component.Common.Type : neotree.Component
---@field [1] "type"?
---@field width integer?

---@param config neotree.Component.Common.Type
M.type = function(config, node, state)
  local text = node.ext or node.type
  -- Root node gets column labels
  if node:get_depth() == 1 then
    return {
      text = get_header(state, "Type", config.width),
      highlight = highlights.FILE_STATS_HEADER,
    }
  end

  return {
    text = vim.fn.printf("%" .. config.width .. "s  ", truncate_string(text, config.width)),
    highlight = highlights.FILE_STATS,
  }
end

return M
