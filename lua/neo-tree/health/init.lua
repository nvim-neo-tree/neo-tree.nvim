local typecheck = require("neo-tree.health.typecheck")
local proxy = require("neo-tree.utils.proxy")
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
---@generic T
---@param proxied T
---@param validator neotree.health.Validator<T>
---@param optional? boolean Whether value can be nil
---@param message? string message when validation fails
---@param on_invalid? fun(err: string, value: T):boolean? What to do when a (nested) validation fails, return true to throw error
local pvalidate = function(proxied, validator, optional, message, on_invalid)
  vim.print(tostring(proxied), type(proxied))
  return validate(tostring(proxied), proxied, validator, optional, message, on_invalid)
end
---@param t table
---@return string[]
local function get_all_key_path_strings(t, key_path_strings, stack)
  key_path_strings = key_path_strings or {}
  stack = stack or {}
  for k, v in pairs(t) do
    stack[#stack + 1] = k
    if type(v) == "table" then
      get_all_key_path_strings(v, key_path_strings, stack)
    else
      key_path_strings[#key_path_strings + 1] = proxy._key_path_tostring(stack)
    end
    stack[#stack] = nil
  end
  return key_path_strings
end

---@module "neo-tree.types.config"
---@param config neotree.Config.Base
---@return boolean
function M.check_config(config)
  ---@type [string, string?][]
  local errors = {}
  local verbose = vim.o.verbose > 0
  local proxied_config = proxy.new(config, true, true)
  local valid = pvalidate(
    proxied_config,
    function(cfg)
      ---@class neotree.health.Validator.Generators
      local v = {
        array = function(validator)
          ---@generic T
          ---@param arr T[]
          return function(arr)
            for i, val in ipairs(arr) do
              pvalidate(("[%d]"):format(i), val, validator)
            end
          end
        end,
        ---@generic T
        ---@param literals T[]
        ---@return fun(a: T):boolean
        literal = function(literals)
          return function(value)
            return vim.tbl_contains(literals, value),
              ("value %s did not match literals %s"):format(value, table.concat(literals, "|"))
          end
        end,
      }
      local schema = {
        LogLevel = v.literal({
          "trace",
          "debug",
          "info",
          "warn",
          "error",
          "fatal",
          vim.log.levels.TRACE,
          vim.log.levels.DEBUG,
          vim.log.levels.INFO,
          vim.log.levels.WARN,
          vim.log.levels.ERROR,
          vim.log.levels.ERROR + 1,
        }),
        Filesystem = {
          ---@param follow_current_file neotree.Config.Filesystem.FollowCurrentFile
          FollowCurrentFile = function(follow_current_file)
            pvalidate(follow_current_file.enabled, "boolean", true)
            pvalidate(follow_current_file.leave_dirs_open, "boolean", true)
          end,
        },

        ---@param window neotree.Config.Window
        Window = function(window)
          pvalidate(window.mappings, "table") -- TODO: More specific validation for mappings table
        end,
        SourceSelector = {
          ---@param item neotree.Config.SourceSelector.Item
          Item = function(item)
            pvalidate(item.source, "string")
            pvalidate(item.padding, { "number", "table" }, true) -- TODO: More specific validation for padding table
            pvalidate(item.separator, { "string", "table" }, true) -- TODO: More specific validation for separator table
          end,
          ---@param sep neotree.Config.SourceSelector.Separator
          Separator = function(sep)
            pvalidate(sep.left, "string")
            pvalidate(sep.right, "string")
            pvalidate(sep.override, v.literal({ "right", "left", "active" }), true)
          end,
        },
        Renderers = v.array("table"),
      }
      ---@param log_level neotree.Logger.Config.Level
      schema.ConfigLogLevel = function(log_level)
        if type(log_level) == "table" then
          return pvalidate(log_level, function(ll)
            pvalidate(ll.console, schema.LogLevel)
            pvalidate(ll.file, schema.LogLevel)
          end)
        else
          pvalidate(log_level, schema.LogLevel)
        end
      end

      if not pvalidate(cfg, "table") then
        health.warn("Config does not exist")
        return
      end

      pvalidate(cfg.sources, v.array("string"), false)
      pvalidate(cfg.add_blank_line_at_top, "boolean")
      pvalidate(cfg.auto_clean_after_session_restore, "boolean")
      pvalidate(cfg.close_if_last_window, "boolean")
      pvalidate(cfg.default_source, "string")
      pvalidate(cfg.enable_diagnostics, "boolean")
      pvalidate(cfg.enable_git_status, "boolean")
      pvalidate(cfg.enable_modified_markers, "boolean")
      pvalidate(cfg.enable_opened_markers, "boolean")
      pvalidate(cfg.enable_refresh_on_write, "boolean")
      pvalidate(cfg.enable_cursor_hijack, "boolean")
      pvalidate(cfg.git_status_async, "boolean")
      pvalidate(cfg.git_status_async_options, function(options)
        pvalidate(options.batch_size, "number")
        pvalidate(options.batch_delay, "number")
        pvalidate(options.max_lines, "number")
      end)
      pvalidate(cfg.hide_root_node, "boolean")
      pvalidate(cfg.retain_hidden_root_indent, "boolean")
      pvalidate(cfg.keep_altfile, "boolean")
      pvalidate(cfg.log_level, schema.ConfigLogLevel, true)
      pvalidate(cfg.log_to_file, { "boolean", "string" })
      pvalidate(cfg.open_files_in_last_window, "boolean")
      pvalidate(cfg.open_files_do_not_replace_types, v.array("string"))
      pvalidate(cfg.open_files_using_relative_paths, "boolean")
      pvalidate(
        cfg.popup_border_style,
        v.literal({ "NC", "rounded", "single", "solid", "double", "" })
      )
      pvalidate(cfg.resize_timer_interval, "number")
      pvalidate(cfg.sort_case_insensitive, "boolean")
      pvalidate(cfg.sort_function, "function", true)
      pvalidate(cfg.use_popups_for_input, "boolean")
      pvalidate(cfg.use_default_mappings, "boolean")
      pvalidate(cfg.source_selector, function(ss)
        pvalidate(ss.winbar, "boolean")
        pvalidate(ss.statusline, "boolean")
        pvalidate(ss.show_scrolled_off_parent_node, "boolean")
        pvalidate(ss.sources, v.array(schema.SourceSelector.Item))
        pvalidate(ss.content_layout, v.literal({ "start", "end", "center" }))
        pvalidate(ss.tabs_layout, v.literal({ "equal", "start", "end", "center", "active" }))
        pvalidate(ss.truncation_character, "string", false)
        pvalidate(ss.tabs_min_width, "number", true)
        pvalidate(ss.tabs_max_width, "number", true)
        pvalidate(ss.padding, { "number", "table" }) -- TODO: More specific validation for padding table
        pvalidate(ss.separator, schema.SourceSelector.Separator)
        pvalidate(ss.separator_active, schema.SourceSelector.Separator, true)
        pvalidate(ss.show_separator_on_edge, "boolean")
        pvalidate(ss.highlight_tab, "string")
        pvalidate(ss.highlight_tab_active, "string")
        pvalidate(ss.highlight_background, "string")
        pvalidate(ss.highlight_separator, "string")
        pvalidate(ss.highlight_separator_active, "string")
      end)
      pvalidate(cfg.event_handlers, v.array("table"), true) -- TODO: More specific validation for event handlers
      pvalidate(cfg.default_component_configs, function(defaults)
        pvalidate(defaults.container, "table") -- TODO: More specific validation
        pvalidate(defaults.indent, "table") -- TODO: More specific validation
        pvalidate(defaults.icon, "table") -- TODO: More specific validation
        pvalidate(defaults.modified, "table") -- TODO: More specific validation
        pvalidate(defaults.name, "table") -- TODO: More specific validation
        pvalidate(defaults.git_status, "table") -- TODO: More specific validation
        pvalidate(defaults.file_size, "table") -- TODO: More specific validation
        pvalidate(defaults.type, "table") -- TODO: More specific validation
        pvalidate(defaults.last_modified, "table") -- TODO: More specific validation
        pvalidate(defaults.created, "table") -- TODO: More specific validation
        pvalidate(defaults.symlink_target, "table") -- TODO: More specific validation
      end)
      pvalidate(cfg.renderers, schema.Renderers)
      pvalidate(cfg.nesting_rules, v.array("table"), true) -- TODO: More specific validation for nesting rules
      pvalidate(cfg.commands, "table", true) -- TODO: More specific validation for commands
      pvalidate(cfg.window, function(window)
        pvalidate(window.position, "string") -- TODO: More specific validation
        pvalidate(window.width, "number")
        pvalidate(window.height, "number")
        pvalidate(window.auto_expand_width, "boolean")
        pvalidate(window.popup, function(popup)
          pvalidate(popup.title, "function")
          pvalidate(popup.size, function(size)
            pvalidate(size.height, { "string", "number" })
            pvalidate(size.width, { "string", "number" })
          end)
          pvalidate(
            popup.border,
            v.literal({ "NC", "rounded", "single", "solid", "double", "" }),
            true
          )
        end)
        pvalidate(window.insert_as, v.literal({ "child", "sibling" }), true)
        pvalidate(window.mapping_options, "table") -- TODO: More specific validation
        pvalidate(window.mappings, v.array("table")) -- TODO: More specific validation for mapping items
      end)

      pvalidate(cfg.filesystem, function(fs)
        pvalidate(fs.async_directory_scan, v.literal({ "auto", "always", "never" }))
        pvalidate(fs.scan_mode, v.literal({ "shallow", "deep" }))
        pvalidate(fs.bind_to_cwd, "boolean")
        pvalidate(fs.cwd_target, function(cwd_target)
          pvalidate(cwd_target.sidebar, v.literal({ "tab", "window", "global" }))
          pvalidate(cwd_target.current, v.literal({ "tab", "window", "global" }))
        end)
        pvalidate(fs.check_gitignore_in_search, "boolean")
        pvalidate(fs.filtered_items, function(f)
          pvalidate(f.visible, "boolean")
          pvalidate(f.force_visible_in_empty_folder, "boolean")
          pvalidate(f.children_inherit_highlights, "boolean")
          pvalidate(f.show_hidden_count, "boolean")
          pvalidate(f.hide_dotfiles, "boolean")
          pvalidate(f.hide_gitignored, "boolean")
          pvalidate(f.hide_ignored, "boolean")
          pvalidate(f.hide_hidden, "boolean")
          pvalidate(f.hide_by_name, v.array("string"))
          pvalidate(f.hide_by_pattern, v.array("string"))
          pvalidate(f.always_show, v.array("string"))
          pvalidate(f.always_show_by_pattern, v.array("string"))
          pvalidate(f.never_show, v.array("string"))
          pvalidate(f.never_show_by_pattern, v.array("string"))
        end)
        pvalidate(fs.find_by_full_path_words, "boolean")
        pvalidate(fs.find_command, "string", true)
        pvalidate(fs.find_args, { "table", "function" }, true)
        pvalidate(fs.group_empty_dirs, "boolean")
        pvalidate(fs.search_limit, "number")
        pvalidate(fs.follow_current_file, schema.Filesystem.FollowCurrentFile)
        pvalidate(
          fs.hijack_netrw_behavior,
          v.literal({ "open_default", "open_current", "disabled" }),
          true
        )
        pvalidate(fs.use_libuv_file_watcher, "boolean")
        pvalidate(fs.renderers, schema.Renderers)
        pvalidate(fs.window, function(window)
          pvalidate(window.mappings, "table") -- TODO: More specific validation for mappings table
          pvalidate(window.fuzzy_finder_mappings, "table") -- TODO: More specific validation
        end)
      end)
      pvalidate(cfg.buffers, function(buffers)
        pvalidate(buffers.bind_to_cwd, "boolean")
        pvalidate(buffers.follow_current_file, schema.Filesystem.FollowCurrentFile)
        pvalidate(buffers.group_empty_dirs, "boolean")
        pvalidate(buffers.show_unloaded, "boolean")
        pvalidate(buffers.terminals_first, "boolean")
        pvalidate(buffers.renderers, schema.Renderers)
        pvalidate(buffers.window, schema.Window)
      end)
      pvalidate(cfg.git_status, function(git_status)
        pvalidate(git_status.renderers, schema.Renderers)
        pvalidate(git_status.window, schema.Window)
      end)
      pvalidate(cfg.document_symbols, function(ds)
        pvalidate(ds.follow_cursor, "boolean")
        pvalidate(ds.client_filters, { "string", "table" }) -- TODO: More specific validation
        pvalidate(ds.custom_kinds, "table") -- TODO: More specific validation
        pvalidate(ds.kinds, "table")
        pvalidate(ds.renderers, schema.Renderers)
        pvalidate(ds.window, schema.Window)
      end)
      pvalidate(cfg.clipboard, function(clip)
        pvalidate(clip.sync, function(sync)
          if type(sync) == "string" then
            return vim.tbl_contains({ "global", "none", "universal" }, sync)
          elseif type(sync) == "table" then
            pvalidate(sync.new, "callable")
            pvalidate(sync.load, "callable")
            pvalidate(sync.save, "callable")
          else
            return false
          end
        end, true)
      end, true)
    end,
    false,
    nil,
    function(err)
      errors[#errors + 1] = { err }
    end
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
    local missed = {}
    for i, s in ipairs(get_all_key_path_strings(config)) do
      missed[s] = true
    end
    ---@type neotree.utils.ProxyMetatable
    local mt = getmetatable(proxied_config)
    local accesses = assert(mt.metadata.accesses)
    for i, key_path in ipairs(accesses) do
      missed[tostring(key_path)] = nil
    end
    for miss in pairs(missed) do
      vim.health.info(miss)
    end
  end

  return valid
end

return M
