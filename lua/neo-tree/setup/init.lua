local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")
local mapping_helper = require("neo-tree.setup.mapping-helper")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local highlights = require("neo-tree.ui.highlights")
local manager = require("neo-tree.sources.manager")
local netrw   = require("neo-tree.setup.netrw")

-- If you add a new source, you need to add it to the sources table.
-- Each source should have a defaults module that contains the default values
-- for the source config, and a setup function that takes that config.
local sources = {
  "filesystem",
  "buffers",
  "git_status",
}

local M = {}

local normalize_mappings = function(config)
  if config == nil then
    return false
  end
  local mappings = utils.get_value(config, "window.mappings", nil)
  if mappings then
    local fixed = mapping_helper.normalize_map(mappings)
    config.window.mappings = fixed
    return true
  else
    return false
  end
end

local events_setup = false
local define_events = function()
  if events_setup then
    return
  end

  local v = vim.version()
  local diag_autocmd = "DiagnosticChanged"
  if v.major < 1 and v.minor < 6 then
    diag_autocmd = "User LspDiagnosticsChanged"
  end
  events.define_autocmd_event(events.VIM_DIAGNOSTIC_CHANGED, { diag_autocmd }, 500, function(args)
    args.diagnostics_lookup = utils.get_diagnostic_counts()
    return args
  end)

  events.define_autocmd_event(events.VIM_BUFFER_CHANGED, { "BufWritePost", "BufFilePost" }, 200)
  events.define_autocmd_event(events.VIM_BUFFER_ADDED, { "BufAdd" }, 200)
  events.define_autocmd_event(events.VIM_BUFFER_DELETED, { "BufDelete" }, 200)
  events.define_autocmd_event(events.VIM_BUFFER_ENTER, { "BufEnter", "BufWinEnter" }, 0)
  events.define_autocmd_event(events.VIM_WIN_ENTER, { "WinEnter" }, 0)
  events.define_autocmd_event(events.VIM_DIR_CHANGED, { "DirChanged" }, 200)
  events.define_autocmd_event(events.VIM_TAB_CLOSED, { "TabClosed" })
  events.define_autocmd_event(events.VIM_COLORSCHEME, { "ColorScheme" }, 0)
  events.define_event(events.GIT_STATUS_CHANGED, { debounce_frequency = 0 })
  events_setup = true
end

M.buffer_enter_event = function()
  -- if it is a neo-tree window, just set local options
  if vim.bo.filetype == "neo-tree" then
    vim.cmd([[
    setlocal cursorline
    setlocal nowrap
    setlocal winhighlight=Normal:NeoTreeNormal,NormalNC:NeoTreeNormalNC,CursorLine:NeoTreeCursorLine,FloatBorder:NeoTreeFloatBorder
    setlocal nolist nospell nonumber norelativenumber
    ]])
    return
  end
  if vim.bo.filetype == "neo-tree-popup" then
    vim.cmd([[
    setlocal winhighlight=Normal:NeoTreeNormal,FloatBorder:NeoTreeFloatBorder
    setlocal nolist nospell nonumber norelativenumber
    ]])
    return
  end

  -- there is nothing more we want to do with floating windows
  if utils.is_floating() then
    return
  end

  -- if vim is trying to open a dir, then we hijack it
  if netrw.hijack() then
    return
  end

  -- For all others, make sure another buffer is not hijacking our window
  -- ..but not if the position is "current"
  local prior_buf = vim.fn.bufnr("#")
  if prior_buf < 1 then
    return
  end
  local prior_type = vim.api.nvim_buf_get_option(prior_buf, "filetype")
  if prior_type == "neo-tree" then
    local position = vim.api.nvim_buf_get_var(prior_buf, "neo_tree_position")
    if position == "current" then
      -- nothing to do here, files are supposed to open in same window
      return
    end

    local current_tabnr = vim.api.nvim_get_current_tabpage()
    local neo_tree_tabnr = vim.api.nvim_buf_get_var(prior_buf, "neo_tree_tabnr")
    if neo_tree_tabnr ~= current_tabnr then
      -- This a new tab, so the alternate being neo-tree doesn't matter.
      return
    end
    local neo_tree_winid = vim.api.nvim_buf_get_var(prior_buf, "neo_tree_winid")
    local current_winid = vim.api.nvim_get_current_win()
    if neo_tree_winid ~= current_winid then
      -- This is not the neo-tree window, so the alternate being neo-tree doesn't matter.
      return
    end

    local bufname = vim.api.nvim_buf_get_name(0)
    log.debug("redirecting buffer " .. bufname .. " to new split")
    vim.cmd("b#")
    -- Using schedule at this point  fixes problem with syntax
    -- highlighting in the buffer. I also prevents errors with diagnostics
    -- trying to work with the buffer as it's being closed.
    vim.schedule(function()
      -- try to delete the buffer, only because if it was new it would take
      -- on options from the neo-tree window that are undesirable.
      pcall(vim.cmd, "bdelete " .. bufname)
      local fake_state = {
        window = {
          position = position,
        },
      }
      utils.open_file(fake_state, bufname)
    end)
  end
end

M.win_enter_event = function()
  local win_id = vim.api.nvim_get_current_win()
  if utils.is_floating(win_id) then
    return
  end

  -- if the new win is not a floating window, make sure all neo-tree floats are closed
  require("neo-tree").close_all("float")

  if M.config.close_if_last_window then
    local tabnr = vim.api.nvim_get_current_tabpage()
    local wins = utils.get_value(M, "config.prior_windows", {})[tabnr]
    local prior_exists = utils.truthy(wins)
    local non_floating_wins = vim.tbl_filter(function(win)
      return not utils.is_floating(win)
    end, vim.api.nvim_tabpage_list_wins(tabnr))
    local win_count = #non_floating_wins
    log.trace("checking if last window")
    log.trace("prior window exists = ", prior_exists)
    log.trace("win_count: ", win_count)
    if prior_exists and win_count == 1 and vim.o.filetype == "neo-tree" then
      local position = vim.api.nvim_buf_get_var(0, "neo_tree_position")
      if position ~= "current" then
        -- close_if_last_window just doesn't make sense for a split style
        log.trace("last window, closing")
        vim.cmd("q!")
        return
      end
    end
  end

  if vim.o.filetype == "neo-tree" then
    -- it's a neo-tree window, ignore
    return
  end

  M.config.prior_windows = M.config.prior_windows or {}

  local tabnr = vim.api.nvim_get_current_tabpage()
  local tab_windows = M.config.prior_windows[tabnr]
  if tab_windows == nil then
    tab_windows = {}
    M.config.prior_windows[tabnr] = tab_windows
  end
  table.insert(tab_windows, win_id)

  -- prune the history when it gets too big
  if #tab_windows > 100 then
    local new_array = {}
    local win_count = #tab_windows
    for i = 80, win_count do
      table.insert(new_array, tab_windows[i])
    end
    M.config.prior_windows[tabnr] = new_array
  end
end


M.set_log_level = function(level)
  log.set_level(level)
end

local function merge_global_components_config(components, config)
  local indent_exists = false
  local merged_components = {}
  for _, component in ipairs(components) do
    local name = component[1]
    if type(name) == "string" then
      if name == "indent" then
        indent_exists = true
      end
      local merged = { name }
      local global_config = config.default_component_configs[name]
      if global_config then
        for k, v in pairs(global_config) do
          merged[k] = v
        end
      end
      for k, v in pairs(component) do
        merged[k] = v
      end
      table.insert(merged_components, merged)
    else
      log.error("component name is the wrong type", component)
    end
  end

  -- If the indent component is not specified, then add it.
  -- We do this because it used to be implicitly added, so we don't want to
  -- break any existing configs.
  if not indent_exists then
    local indent = { "indent" }
    for k, v in pairs(config.default_component_configs.indent or {}) do
      indent[k] = v
    end
    table.insert(merged_components, 1, indent)
  end
  return merged_components
end

M.merge_config = function(config, is_auto_config)
  local default_config = vim.deepcopy(defaults)
  config = vim.deepcopy(config or {})

  local messages = require("neo-tree.setup.deprecations").migrate(config)
  if #messages > 0 then
    for i, message in ipairs(messages) do
      messages[i] = "  * " .. message
    end
    table.insert(messages, 1, "# Neo-tree configuration has been updated. Please review the changes below.")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, messages)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "buflisted", false)
    vim.api.nvim_buf_set_option(buf, "swapfile", false)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
    vim.defer_fn(function ()
      vim.cmd("split")
      vim.api.nvim_win_set_buf(0, buf)
    end, 100)
  end

  if config.log_level ~= nil then
    M.set_log_level(config.log_level)
  end
  log.use_file(config.log_to_file, true)
  log.debug("setup")

  events.clear_all_events()
  define_events()

  -- Prevent accidentally opening another file in the neo-tree window.
  events.subscribe({
    event = events.VIM_BUFFER_ENTER,
    handler = M.buffer_enter_event,
  })

  if config.event_handlers ~= nil then
    for _, handler in ipairs(config.event_handlers) do
      events.subscribe(handler)
    end
  end

  highlights.setup()

  -- setup the default values for all sources
  normalize_mappings(default_config)
  for _, source_name in ipairs(sources) do
    local source_config = default_config[source_name]
    local mod_root = "neo-tree.sources." .. source_name
    source_config.components = require(mod_root .. ".components")
    source_config.commands = require(mod_root .. ".commands")
    source_config.name = source_name

    -- Make sure all the mappings are normalized so they will merge properly.
    normalize_mappings(source_config)
    normalize_mappings(config[source_name])

    -- merge the global config with the source specific config
    source_config.window = utils.table_merge(default_config.window or {}, source_config.window or {})
    source_config.renderers = source_config.renderers or {}
    -- if source does not specify a renderer, use the global default
    for name, renderer in pairs(default_config.renderers or {}) do
      if source_config.renderers[name] == nil then
        local r = {}
        for  _, value in ipairs(renderer) do
          if value[1] and source_config.components[value[1]] ~= nil then
            table.insert(r, value)
          end
        end
        source_config.renderers[name] = r
      end
    end
    -- if user sets renderers, completely wipe the default ones
    for name, _ in pairs(source_config.renderers) do
      local user = utils.get_value(config, source_name .. ".renderers." .. name)
      if user then
        source_config.renderers[name] = nil
      end
    end

    --validate the window.position
    local pos_key = source_name .. ".window.position"
    local position = utils.get_value(config, pos_key, "left", true)
    local valid_positions = {
      left = true,
      right = true,
      top = true,
      bottom = true,
      float = true,
      current = true,
    }
    if not valid_positions[position] then
      log.error("Invalid value for ", pos_key, ": ", position)
      config[source_name].window.position = "left"
    end
  end

  -- apply the users config
  M.config = utils.table_merge(default_config, config)

  for _, source_name in ipairs(sources) do
    for name, rndr in pairs(M.config[source_name].renderers) do
      M.config[source_name].renderers[name] = merge_global_components_config(rndr, M.config)
    end
    manager.setup(source_name, M.config[source_name], M.config)
    manager.redraw(source_name)
  end

  events.subscribe({
    event = events.VIM_COLORSCHEME,
    handler = highlights.setup,
    id = "neo-tree-highlight",
  })

  events.subscribe({
    event = events.VIM_WIN_ENTER,
    handler = M.win_enter_event,
    id = "neo-tree-win-enter",
  })

  if not is_auto_config and netrw.get_hijack_netrw_behavior() ~= "disabled" then
    vim.cmd("silent! autocmd! FileExplorer *")
  end

  return M.config
end

return M
