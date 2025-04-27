local M = {}
local health = vim.health

local function check_dependencies()
  local devicons_ok = pcall(require, "nvim-web-devicons")
  if devicons_ok then
    health.ok("nvim-web-devicons is installed")
  else
    health.info("nvim-web-devicons not installed")
  end

  local plenary_ok = pcall(require, "plenary")
  if plenary_ok then
    health.ok("plenary.nvim is installed")
  else
    health.error("plenary.nvim is not installed")
  end

  local nui_ok = pcall(require, "nui.tree")
  if nui_ok then
    health.ok("nui.nvim is installed")
  else
    health.error("nui.nvim not installed")
  end
end

local vim_validate_new
if vim.fn.has("nvim-0.11") == 1 then
  vim_validate_new = vim.validate
else
  ---@alias neotree.Health.Type type|"callable"
  ---@alias neotree.Health.Types neotree.Health.Type|(neotree.Health.Type[])

  ---@param obj any
  ---@param expected neotree.Health.Types
  ---@return boolean matches
  local matches_type = function(obj, expected)
    if type(obj) == expected then
      return true
    end
    if expected == "callable" and vim.is_callable(obj) then
      return true
    end
    return false
  end

  vim_validate_new = function(name, value, validator, optional, message)
    local matched, errmsg, errinfo
    if type(validator) == "string" then
      matched = matches_type(value, validator)
    elseif type(validator) == "table" then
      for _, v in ipairs(validator) do
        matched = matches_type(value, v)
        if matched then
          break
        end
      end
    elseif vim.is_callable(validator) and value ~= nil then
      matched, errinfo = validator(value)
    end
    matched = matched or (optional and value == nil)
    if not matched then
      local expected_types = type(validator) == "string" and { validator } or validator
      if optional then
        expected_types[#expected_types + 1] = "nil"
      end
      local expected = vim.is_callable(expected_types) and "?" or table.concat(expected_types, "|")
      errmsg = ("%s: %s, got %s"):format(
        name,
        message or ("expected " .. expected),
        message and value or type(value)
      )
      if errinfo then
        errmsg = errmsg .. ", Info: " .. errinfo
      end
      error(errmsg, 2)
    end
  end
end
---@param config neotree.Config.Base
function M.check_config(config)
  ---@type [string, string][]
  local errors = {}

  ---@type string[]
  local index_path = {}
  local full_path = ""

  ---@generic T string
  ---@param name string Argument name
  ---@param value T Argument value
  ---@param validator type|type[]|"callable"|fun(value: T):boolean?,string?
  ---@param optional? boolean Argument is optional (may be omitted)
  ---@param advice? string message when validation fails
  ---@return boolean valid
  ---@return string? errmsg
  local validate = function(name, value, validator, optional, advice)
    if type(validator) == "function" and type(value) == "table" then
      table.insert(index_path, name)
      full_path = table.concat(index_path, ".") .. "."
      local valid, errmsg = validator(value)
      table.remove(index_path)
      full_path = table.concat(index_path, ".") .. "."
      if valid == nil then
        valid = true
      end
      return valid, errmsg
    end

    -- do regular validate
    local valid, errmsg = pcall(vim_validate_new, full_path .. name, value, validator, optional)
    if not valid then
      -- if type(validator) == "string" then
      --   advice = advice or ("Change this option to a %s"):format(validator)
      -- elseif type(validator) == "table" then
      --   advice = advice or ("Change this option to a %s"):format(table.concat(validator, "|"))
      -- end
      table.insert(errors, {
        errmsg,
        -- advice,
      })
    end
    return valid, errmsg
  end

  ---@class neotree.Validator.Generators
  ---@field [string] fun(...):(fun(value: any):boolean,string?)
  local validator = {
    array = function(validator)
      ---@generic T
      ---@param arr T[]
      return function(arr)
        for i, val in ipairs(arr) do
          validate(("[%d]"):format(i), val, validator)
        end
      end
    end,
    literal = function(literals)
      return function(value)
        return vim.tbl_contains(literals, value),
          ("value %s did not match literals %s"):format(value, table.concat(literals, "|"))
      end
    end,
  }
  local schema = {
    Filesystem = {
      ---@param follow_current_file neotree.Config.Filesystem.FollowCurrentFile
      FollowCurrentFile = function(follow_current_file)
        validate("enabled", follow_current_file.enabled, "boolean", true)
        validate("leave_dirs_open", follow_current_file.leave_dirs_open, "boolean", true)
      end,
    },

    Source = {
      ---@param window neotree.Config.Source.Window
      Window = function(window)
        validate("mappings", window.mappings, "table") -- TODO: More specific validation for mappings table
      end,
    },
    SourceSelector = {
      ---@param item neotree.Config.SourceSelector.Item
      Item = function(item)
        validate("source", item.source, "string")
        validate("padding", item.padding, { "number", "table" }, true) -- TODO: More specific validation for padding table
        validate("separator", item.separator, { "string", "table" }, true) -- TODO: More specific validation for separator table
      end,
      ---@param sep neotree.Config.SourceSelector.Separator
      Separator = function(sep)
        validate("left", sep.left, "string")
        validate("right", sep.right, "string")
        validate(
          "override",
          sep.override,
          validator.literal({ "right", "left", "active", "nil" }),
          true
        )
      end,
    },
    Renderers = validator.array("table"),
  }

  if not validate("config", config, "table", false) then
    health.error("Config does not exist")
    return
  end

  validate("sources", config.sources, validator.array("string"), false)
  validate("add_blank_line_at_top", config.add_blank_line_at_top, "boolean")
  validate("auto_clean_after_session_restore", config.auto_clean_after_session_restore, "boolean")
  validate("close_if_last_window", config.close_if_last_window, "boolean")
  validate("default_source", config.default_source, "string")
  validate("enable_diagnostics", config.enable_diagnostics, "boolean")
  validate("enable_git_status", config.enable_git_status, "boolean")
  validate("enable_modified_markers", config.enable_modified_markers, "boolean")
  validate("enable_opened_markers", config.enable_opened_markers, "boolean")
  validate("enable_refresh_on_write", config.enable_refresh_on_write, "boolean")
  validate("enable_cursor_hijack", config.enable_cursor_hijack, "boolean")
  validate("git_status_async", config.git_status_async, "boolean")
  validate("git_status_async_options", config.git_status_async_options, function(options)
    validate("batch_size", options.batch_size, "number")
    validate("batch_delay", options.batch_delay, "number")
    validate("max_lines", options.max_lines, "number")
  end)
  validate("hide_root_node", config.hide_root_node, "boolean")
  validate("retain_hidden_root_indent", config.retain_hidden_root_indent, "boolean")
  validate(
    "log_level",
    config.log_level,
    validator.literal({ "trace", "debug", "info", "warn", "error", "fatal", "nil" })
  )
  validate("log_to_file", config.log_to_file, { "boolean", "string" })
  validate("open_files_in_last_window", config.open_files_in_last_window, "boolean")
  validate(
    "open_files_do_not_replace_types",
    config.open_files_do_not_replace_types,
    validator.array("string")
  )
  validate("open_files_using_relative_paths", config.open_files_using_relative_paths, "boolean")
  validate(
    "popup_border_style",
    config.popup_border_style,
    validator.literal({ "NC", "rounded", "single", "solid", "double", "" })
  )
  validate("resize_timer_interval", config.resize_timer_interval, "number")
  validate("sort_case_insensitive", config.sort_case_insensitive, "boolean")
  validate("sort_function", config.sort_function, "function", true)
  validate("use_popups_for_input", config.use_popups_for_input, "boolean")
  validate("use_default_mappings", config.use_default_mappings, "boolean")
  validate("source_selector", config.source_selector, function(ss)
    validate("winbar", ss.winbar, "boolean")
    validate("statusline", ss.statusline, "boolean")
    validate("show_scrolled_off_parent_node", ss.show_scrolled_off_parent_node, "boolean")
    validate("sources", ss.sources, validator.array(schema.SourceSelector.Item))
    validate("content_layout", ss.content_layout, validator.literal({ "start", "end", "center" }))
    validate(
      "tabs_layout",
      ss.tabs_layout,
      validator.literal({ "equal", "start", "end", "center", "focus" })
    )
    validate("truncation_character", ss.truncation_character, "string", false)
    validate("tabs_min_width", ss.tabs_min_width, "number", true)
    validate("tabs_max_width", ss.tabs_max_width, "number", true)
    validate("padding", ss.padding, { "number", "table" }) -- TODO: More specific validation for padding table
    validate("separator", ss.separator, schema.SourceSelector.Separator)
    validate("separator_active", ss.separator_active, schema.SourceSelector.Separator, true)
    validate("show_separator_on_edge", ss.show_separator_on_edge, "boolean")
    validate("highlight_tab", ss.highlight_tab, "string")
    validate("highlight_tab_active", ss.highlight_tab_active, "string")
    validate("highlight_background", ss.highlight_background, "string")
    validate("highlight_separator", ss.highlight_separator, "string")
    validate("highlight_separator_active", ss.highlight_separator_active, "string")
  end)
  validate("event_handlers", config.event_handlers, validator.array("table"), true) -- TODO: More specific validation for event handlers
  validate("default_component_configs", config.default_component_configs, function(defaults)
    validate("container", defaults.container, "table") -- TODO: More specific validation
    validate("indent", defaults.indent, "table") -- TODO: More specific validation
    validate("icon", defaults.icon, "table") -- TODO: More specific validation
    validate("modified", defaults.modified, "table") -- TODO: More specific validation
    validate("name", defaults.name, "table") -- TODO: More specific validation
    validate("git_status", defaults.git_status, "table") -- TODO: More specific validation
    validate("file_size", defaults.file_size, "table") -- TODO: More specific validation
    validate("type", defaults.type, "table") -- TODO: More specific validation
    validate("last_modified", defaults.last_modified, "table") -- TODO: More specific validation
    validate("created", defaults.created, "table") -- TODO: More specific validation
    validate("symlink_target", defaults.symlink_target, "table") -- TODO: More specific validation
  end)
  validate("renderers", config.renderers, schema.Renderers)
  validate("nesting_rules", config.nesting_rules, validator.array("table"), true) -- TODO: More specific validation for nesting rules
  validate("commands", config.commands, "table", true) -- TODO: More specific validation for commands
  validate("window", config.window, function(window)
    validate("position", window.position, "string") -- TODO: More specific validation
    validate("width", window.width, "number")
    validate("height", window.height, "number")
    validate("auto_expand_width", window.auto_expand_width, "boolean")
    validate("popup", window.popup, function(popup)
      validate("title", popup.title, "function")
      validate("size", popup.size, function(size)
        validate("height", size.height, { "string", "number" })
        validate("width", size.width, { "string", "number" })
      end)
      validate(
        "border",
        popup.border,
        validator.literal({ "NC", "rounded", "single", "solid", "double", "" }),
        true
      )
    end)
    validate("same_level", window.same_level, "boolean")
    validate("insert_as", window.insert_as, validator.literal({ "child", "sibling", "nil" }))
    validate("mapping_options", window.mapping_options, "table") -- TODO: More specific validation
    validate("mappings", window.mappings, validator.array("table")) -- TODO: More specific validation for mapping items
  end)

  validate("filesystem", config.filesystem, function(fs)
    validate(
      "async_directory_scan",
      fs.async_directory_scan,
      validator.literal({ "auto", "always", "never" })
    )
    validate("scan_mode", fs.scan_mode, validator.literal({ "shallow", "deep" }))
    validate("bind_to_cwd", fs.bind_to_cwd, "boolean")
    validate("cwd_target", fs.cwd_target, function(cwd_target)
      validate("sidebar", cwd_target.sidebar, validator.literal({ "tab", "window", "global" }))
      validate("current", cwd_target.current, validator.literal({ "tab", "window", "global" }))
    end)
    validate("check_gitignore_in_search", fs.check_gitignore_in_search, "boolean")
    validate("filtered_items", fs.filtered_items, function(filtered_items)
      validate("visible", filtered_items.visible, "boolean")
      validate(
        "force_visible_in_empty_folder",
        filtered_items.force_visible_in_empty_folder,
        "boolean"
      )
      validate("show_hidden_count", filtered_items.show_hidden_count, "boolean")
      validate("hide_dotfiles", filtered_items.hide_dotfiles, "boolean")
      validate("hide_gitignored", filtered_items.hide_gitignored, "boolean")
      validate("hide_hidden", filtered_items.hide_hidden, "boolean")
      validate("hide_by_name", filtered_items.hide_by_name, validator.array("string"))
      validate("hide_by_pattern", filtered_items.hide_by_pattern, validator.array("string"))
      validate("always_show", filtered_items.always_show, validator.array("string"))
      validate(
        "always_show_by_pattern",
        filtered_items.always_show_by_pattern,
        validator.array("string")
      )
      validate("never_show", filtered_items.never_show, validator.array("string"))
      validate(
        "never_show_by_pattern",
        filtered_items.never_show_by_pattern,
        validator.array("string")
      )
    end)
    validate("find_by_full_path_words", fs.find_by_full_path_words, "boolean")
    validate("find_command", fs.find_command, "string", true)
    validate("find_args", fs.find_args, { "table", "function" }, true)
    validate("group_empty_dirs", fs.group_empty_dirs, "boolean")
    validate("search_limit", fs.search_limit, "number")
    validate("follow_current_file", fs.follow_current_file, schema.Filesystem.FollowCurrentFile)
    validate(
      "hijack_netrw_behavior",
      fs.hijack_netrw_behavior,
      validator.literal({ "open_default", "open_current", "disabled" }),
      true
    )
    validate("use_libuv_file_watcher", fs.use_libuv_file_watcher, "boolean")
    validate("renderers", fs.renderers, schema.Renderers)
    validate("window", fs.window, function(window)
      validate("mappings", window.mappings, "table") -- TODO: More specific validation for mappings table
      validate("fuzzy_finder_mappings", window.fuzzy_finder_mappings, "table") -- TODO: More specific validation
    end)
  end)
  validate("buffers", config.buffers, function(buffers)
    validate("bind_to_cwd", buffers.bind_to_cwd, "boolean")
    validate(
      "follow_current_file",
      buffers.follow_current_file,
      schema.Filesystem.FollowCurrentFile
    )
    validate("group_empty_dirs", buffers.group_empty_dirs, "boolean")
    validate("show_unloaded", buffers.show_unloaded, "boolean")
    validate("terminals_first", buffers.terminals_first, "boolean")
    validate("renderers", buffers.renderers, schema.Renderers)
    validate("window", buffers.window, schema.Source.Window)
  end)
  validate("git_status", config.git_status, function(git_status)
    validate("renderers", git_status.renderers, schema.Renderers)
    validate("window", git_status.window, schema.Source.Window)
  end)
  validate("document_symbols", config.document_symbols, function(document_symbols)
    validate("follow_cursor", document_symbols.follow_cursor, "boolean")
    validate("client_filters", document_symbols.client_filters, { "string", "table" }) -- TODO: More specific validation
    validate("custom_kinds", document_symbols.custom_kinds, "table") -- TODO: More specific validation
    validate("kinds", document_symbols.kinds, "table")
    validate("renderers", document_symbols.renderers, schema.Renderers)
    validate("window", document_symbols.window, schema.Source.Window)
  end)

  if #errors == 0 then
    health.ok("Configuration conforms to schema")
  else
    for _, err in ipairs(errors) do
      health.error(unpack(err))
    end
  end
  health.info("(Config schema checking is not comprehensive yet)")
end

function M.check()
  health.start("Neo-tree")
  check_dependencies()
  local config = require("neo-tree").ensure_config()
  M.check_config(config)
end

return M
