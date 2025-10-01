local typecheck = require("neo-tree.health.typecheck")
local health = vim.health

local M = {}

---@param modname string
---@param repo string
---@param optional boolean?
local check_dependency = function(modname, repo, optional)
  local m = pcall(require, modname)
  if not m then
    local errmsg = repo .. " is not installed"
    if optional then
      health.info(errmsg)
    else
      health.error(errmsg)
    end
    return
  end

  health.ok(repo .. " is installed")
end

function M.check()
  health.start("Dependencies")
  check_dependency("plenary", "nvim-lua/plenary.nvim")
  check_dependency("nui.tree", "MunifTanjim/nui.nvim")

  health.start("Optional icons")
  check_dependency("nvim-web-devicons", "nvim-tree/nvim-web-devicons", true)

  health.start("Optional preview image support (only need one):")
  check_dependency("snacks.image", "folke/snacks.nvim", true)
  check_dependency("image", "3rd/image.nvim", true)

  health.start("Optional LSP integration for commands (like copy/delete/move/etc.)")
  check_dependency("lsp-file-operations", "antosha417/nvim-lsp-file-operations", true)

  health.start("Optional window picker (for _with_window_picker commands)")
  check_dependency("window-picker", "s1n7ax/nvim-window-picker", true)

  health.start("Configuration")
  local config = require("neo-tree").ensure_config()
  M.check_config(config)
end

local validate = typecheck.validate

---@module "neo-tree.types.config"
---@param config neotree.Config.Base
---@return boolean
function M.check_config(config)
  ---@type [string, string?][]
  local errors = {}
  local verbose = vim.o.verbose > 0
  local valid, missed = validate(
    "config",
    config,
    function(cfg)
      ---@class neotree.health.Validator.Generators
      local v = {
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

        ---@param window neotree.Config.Window
        Window = function(window)
          validate("mappings", window.mappings, "table") -- TODO: More specific validation for mappings table
        end,
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
            validate("override", sep.override, v.literal({ "right", "left", "active" }), true)
          end,
        },
        Renderers = v.array("table"),
      }

      if not validate("config", cfg, "table") then
        health.error("Config does not exist")
        return
      end

      validate("sources", cfg.sources, v.array("string"), false)
      validate("add_blank_line_at_top", cfg.add_blank_line_at_top, "boolean")
      validate("auto_clean_after_session_restore", cfg.auto_clean_after_session_restore, "boolean")
      validate("close_if_last_window", cfg.close_if_last_window, "boolean")
      validate("default_source", cfg.default_source, "string")
      validate("enable_diagnostics", cfg.enable_diagnostics, "boolean")
      validate("enable_git_status", cfg.enable_git_status, "boolean")
      validate("enable_modified_markers", cfg.enable_modified_markers, "boolean")
      validate("enable_opened_markers", cfg.enable_opened_markers, "boolean")
      validate("enable_refresh_on_write", cfg.enable_refresh_on_write, "boolean")
      validate("enable_cursor_hijack", cfg.enable_cursor_hijack, "boolean")
      validate("git_status_async", cfg.git_status_async, "boolean")
      validate("git_status_async_options", cfg.git_status_async_options, function(options)
        validate("batch_size", options.batch_size, "number")
        validate("batch_delay", options.batch_delay, "number")
        validate("max_lines", options.max_lines, "number")
      end)
      validate("hide_root_node", cfg.hide_root_node, "boolean")
      validate("retain_hidden_root_indent", cfg.retain_hidden_root_indent, "boolean")
      validate(
        "log_level",
        cfg.log_level,
        v.literal({ "trace", "debug", "info", "warn", "error", "fatal" }),
        true
      )
      validate("log_to_file", cfg.log_to_file, { "boolean", "string" })
      validate("open_files_in_last_window", cfg.open_files_in_last_window, "boolean")
      validate(
        "open_files_do_not_replace_types",
        cfg.open_files_do_not_replace_types,
        v.array("string")
      )
      validate("open_files_using_relative_paths", cfg.open_files_using_relative_paths, "boolean")
      validate(
        "popup_border_style",
        cfg.popup_border_style,
        v.literal({ "NC", "rounded", "single", "solid", "double", "" })
      )
      validate("resize_timer_interval", cfg.resize_timer_interval, "number")
      validate("sort_case_insensitive", cfg.sort_case_insensitive, "boolean")
      validate("sort_function", cfg.sort_function, "function", true)
      validate("use_popups_for_input", cfg.use_popups_for_input, "boolean")
      validate("use_default_mappings", cfg.use_default_mappings, "boolean")
      validate("source_selector", cfg.source_selector, function(ss)
        validate("winbar", ss.winbar, "boolean")
        validate("statusline", ss.statusline, "boolean")
        validate("show_scrolled_off_parent_node", ss.show_scrolled_off_parent_node, "boolean")
        validate("sources", ss.sources, v.array(schema.SourceSelector.Item))
        validate("content_layout", ss.content_layout, v.literal({ "start", "end", "center" }))
        validate(
          "tabs_layout",
          ss.tabs_layout,
          v.literal({ "equal", "start", "end", "center", "focus" })
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
      validate("event_handlers", cfg.event_handlers, v.array("table"), true) -- TODO: More specific validation for event handlers
      validate("default_component_configs", cfg.default_component_configs, function(defaults)
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
      validate("renderers", cfg.renderers, schema.Renderers)
      validate("nesting_rules", cfg.nesting_rules, v.array("table"), true) -- TODO: More specific validation for nesting rules
      validate("commands", cfg.commands, "table", true) -- TODO: More specific validation for commands
      validate("window", cfg.window, function(window)
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
            v.literal({ "NC", "rounded", "single", "solid", "double", "" }),
            true
          )
        end)
        validate("insert_as", window.insert_as, v.literal({ "child", "sibling" }), true)
        validate("mapping_options", window.mapping_options, "table") -- TODO: More specific validation
        validate("mappings", window.mappings, v.array("table")) -- TODO: More specific validation for mapping items
      end)

      validate("filesystem", cfg.filesystem, function(fs)
        validate(
          "async_directory_scan",
          fs.async_directory_scan,
          v.literal({ "auto", "always", "never" })
        )
        validate("scan_mode", fs.scan_mode, v.literal({ "shallow", "deep" }))
        validate("bind_to_cwd", fs.bind_to_cwd, "boolean")
        validate("cwd_target", fs.cwd_target, function(cwd_target)
          validate("sidebar", cwd_target.sidebar, v.literal({ "tab", "window", "global" }))
          validate("current", cwd_target.current, v.literal({ "tab", "window", "global" }))
        end)
        validate("check_gitignore_in_search", fs.check_gitignore_in_search, "boolean")
        validate("filtered_items", fs.filtered_items, function(f)
          validate("visible", f.visible, "boolean")
          validate("force_visible_in_empty_folder", f.force_visible_in_empty_folder, "boolean")
          validate("children_inherit_highlights", f.children_inherit_highlights, "boolean")
          validate("show_hidden_count", f.show_hidden_count, "boolean")
          validate("hide_dotfiles", f.hide_dotfiles, "boolean")
          validate("hide_gitignored", f.hide_gitignored, "boolean")
          validate("hide_ignored", f.hide_ignored, "boolean")
          validate("hide_hidden", f.hide_hidden, "boolean")
          validate("hide_by_name", f.hide_by_name, v.array("string"))
          validate("hide_by_pattern", f.hide_by_pattern, v.array("string"))
          validate("always_show", f.always_show, v.array("string"))
          validate("always_show_by_pattern", f.always_show_by_pattern, v.array("string"))
          validate("never_show", f.never_show, v.array("string"))
          validate("never_show_by_pattern", f.never_show_by_pattern, v.array("string"))
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
          v.literal({ "open_default", "open_current", "disabled" }),
          true
        )
        validate("use_libuv_file_watcher", fs.use_libuv_file_watcher, "boolean")
        validate("renderers", fs.renderers, schema.Renderers)
        validate("window", fs.window, function(window)
          validate("mappings", window.mappings, "table") -- TODO: More specific validation for mappings table
          validate("fuzzy_finder_mappings", window.fuzzy_finder_mappings, "table") -- TODO: More specific validation
        end)
      end)
      validate("buffers", cfg.buffers, function(buffers)
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
        validate("window", buffers.window, schema.Window)
      end)
      validate("git_status", cfg.git_status, function(git_status)
        validate("renderers", git_status.renderers, schema.Renderers)
        validate("window", git_status.window, schema.Window)
      end)
      validate("document_symbols", cfg.document_symbols, function(ds)
        validate("follow_cursor", ds.follow_cursor, "boolean")
        validate("client_filters", ds.client_filters, { "string", "table" }) -- TODO: More specific validation
        validate("custom_kinds", ds.custom_kinds, "table") -- TODO: More specific validation
        validate("kinds", ds.kinds, "table")
        validate("renderers", ds.renderers, schema.Renderers)
        validate("window", ds.window, schema.Window)
      end)
    end,
    false,
    nil,
    function(err)
      errors[#errors + 1] = { err }
    end,
    true
  )

  if #errors == 0 then
    health.ok("Configuration conforms to the neotree.Config.Base schema")
  else
    for _, err in ipairs(errors) do
      health.error(unpack(err))
    end
  end
  if verbose then
    health.info(
      "[verbose] Config schema checking is not comprehensive yet, unchecked keys listed below:"
    )
    if missed then
      for _, miss in ipairs(missed) do
        health.info(miss)
      end
    end
  end
  return valid
end

return M
