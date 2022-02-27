local vim = vim
local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")
local renderer = require("neo-tree.ui.renderer")
local mapping_helper = require("neo-tree.mapping-helper")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local popups = require("neo-tree.ui.popups")
local highlights = require("neo-tree.ui.highlights")
local manager = require("neo-tree.sources.manager")

-- If you add a new source, you need to add it to the sources table.
-- Each source should have a defaults module that contains the default values
-- for the source config, and a setup function that takes that config.
local sources = {
  "filesystem",
  "buffers",
  "git_status",
}

local M = {}

-- TODO: DEPRECATED in 1.19, remove in 2.0
M.fs = require("neo-tree.sources.filesystem")

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

local ensure_config = function()
  if not M.config then
    M.setup({ log_to_file = false }, true)
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

local check_source = function(source_name)
  if not utils.truthy(source_name) then
    source_name = M.config.default_source
  end
  local success, result = pcall(require, "neo-tree.sources." .. source_name)
  if not success then
    error("Source " .. source_name .. " could not be loaded: ", result)
  end
  return source_name
end

local get_position = function(source_name)
  local pos = utils.get_value(M, "config." .. source_name .. ".window.position", "left")
  return pos
end

local get_hijack_netrw_behavior = function()
  local option = "filesystem.hijack_netrw_behavior"
  local hijack_behavior = utils.get_value(M.config, option, "open_default")
  if hijack_behavior == "disabled" then
    return hijack_behavior
  elseif hijack_behavior == "open_default" then
    return hijack_behavior
  elseif hijack_behavior == "open_split" then
    return hijack_behavior
  else
    log.error("Invalid value for " .. option .. ": " .. hijack_behavior)
    return "disabled"
  end
end

local hijack_netrw = function()
  local hijack_behavior = get_hijack_netrw_behavior()
  if hijack_behavior == "disabled" then
    return false
  end

  -- ensure this is a directory
  local bufname = vim.api.nvim_buf_get_name(0)
  local stats = vim.loop.fs_stat(bufname)
  if not stats then
    return false
  end
  if stats.type ~= "directory" then
    return false
  end

  -- record where we are now
  local should_open_split = hijack_behavior == "open_split" or get_position("filesystem") == "split"
  local winid = vim.api.nvim_get_current_win()
  local dir_bufnr = vim.api.nvim_get_current_buf()

  -- We will want to replace the "directory" buffer with either the "alternate"
  -- buffer or a new blank one.
  local replace_with_bufnr = vim.fn.bufnr("#")
  if replace_with_bufnr > 0 then
    if vim.api.nvim_buf_get_option(replace_with_bufnr, "filetype") == "neo-tree" then
      replace_with_bufnr = -1
    end
  end
  if not should_open_split then
    if replace_with_bufnr == dir_bufnr or replace_with_bufnr < 1 then
      replace_with_bufnr = vim.api.nvim_create_buf(true, false)
    end
  end
  if replace_with_bufnr > 0 then
    pcall(vim.api.nvim_win_set_buf, winid, replace_with_bufnr)
  end
  local remove_dir_buf = vim.schedule_wrap(function()
    pcall(vim.api.nvim_buf_delete, dir_bufnr, { force = true })
  end)

  -- Now actually open the tree, with a very quick debounce because this may be
  -- called multiple times in quick succession.
  utils.debounce("hijack_netrw_" .. winid, function()
    local state
    if should_open_split then
      log.debug("hijack_netrw: opening split")
      state = manager.get_state("filesystem", nil, winid)
      state.current_position = "split"
    else
      log.debug("hijack_netrw: opening default")
      M.close_all_except("filesystem")
      state = manager.get_state("filesystem")
    end
    require("neo-tree.sources.filesystem")._navigate_internal(state, bufname, nil, remove_dir_buf)
  end, 10, utils.debounce_strategy.CALL_LAST_ONLY)

  return true
end

M.close_all_except = function(source_name)
  source_name = check_source(source_name)
  local target_pos = get_position(source_name)
  for _, name in ipairs(sources) do
    if name ~= source_name then
      local pos = utils.get_value(M, "config." .. name .. ".window.position", "left")
      if pos == target_pos then
        manager.close(name)
      end
    end
  end
  renderer.close_all_floating_windows()
end

M.close = manager.close

M.close_all = function(at_position)
  renderer.close_all_floating_windows()
  if type(at_position) == "string" and at_position > "" then
    for _, name in ipairs(sources) do
      local pos = get_position(name)
      if pos == at_position then
        manager.close(name)
      end
    end
  else
    for _, name in ipairs(sources) do
      manager.close(name)
    end
  end
end

M.float = function(source_name, toggle_if_open)
  source_name = check_source(source_name)
  if toggle_if_open then
    if renderer.close_floating_window(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  renderer.close_all_floating_windows()
  manager.close(source_name) -- in case this source is open in a sidebar
  manager.float(source_name)
end

--TODO: Remove the close_others option in 2.0
M.focus = function(source_name, close_others, toggle_if_open)
  source_name = check_source(source_name)
  if get_position(source_name) == "split" then
    M.show_in_split(source_name, toggle_if_open)
    return
  end

  if toggle_if_open then
    if manager.close(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  if close_others == nil then
    close_others = true
  end
  if close_others then
    M.close_all_except(source_name)
  end
  manager.focus(source_name)
end

M.reveal_current_file = function(source_name, toggle_if_open, force_cwd)
  source_name = check_source(source_name)
  if get_position(source_name) == "split" then
    M.reveal_in_split(source_name, toggle_if_open)
    return
  end
  if toggle_if_open then
    if manager.close(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  manager.reveal_current_file(source_name, nil, force_cwd)
end

M.reveal_in_split = function(source_name, toggle_if_open)
  source_name = check_source(source_name)
  if toggle_if_open then
    local state = manager.get_state(source_name, nil, vim.api.nvim_get_current_win())
    if renderer.close(state) then
      -- It was open, and now it's not.
      return
    end
  end
  --TODO: if we are currently in a sidebar, don't replace it with a split style
  manager.reveal_in_split(source_name)
end

M.show_in_split = function(source_name, toggle_if_open)
  source_name = check_source(source_name)
  if toggle_if_open then
    local state = manager.get_state(source_name, nil, vim.api.nvim_get_current_win())
    if renderer.close(state) then
      -- It was open, and now it's not.
      return
    end
  end
  --TODO: if we are currently in a sidebar, don't replace it with a split style
  manager.show_in_split(source_name)
end

M.get_prior_window = function()
  local tabnr = vim.api.nvim_get_current_tabpage()
  local wins = utils.get_value(M, "config.prior_windows", {})[tabnr]
  if wins == nil then
    return -1
  end
  local win_index = #wins
  while win_index > 0 do
    local last_win = wins[win_index]
    if type(last_win) == "number" then
      local success, is_valid = pcall(vim.api.nvim_win_is_valid, last_win)
      if success and is_valid then
        local buf = vim.api.nvim_win_get_buf(last_win)
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        if ft ~= "neo-tree" then
          return last_win
        end
      end
    end
    win_index = win_index - 1
  end
  return -1
end

M.paste_default_config = function()
  local base_path = debug.getinfo(utils.truthy).source:match("@(.*)/utils.lua$")
  local config_path = base_path .. utils.path_separator .. "defaults.lua"
  local lines = vim.fn.readfile(config_path)
  if lines == nil then
    error("Could not read neo-tree.defaults")
  end

  -- read up to the end of the config, jut to omit the final return
  local config = {}
  for _, line in ipairs(lines) do
    table.insert(config, line)
    if line == "}" then
      break
    end
  end

  vim.api.nvim_put(config, "l", true, false)
  vim.schedule(function()
    vim.cmd("normal! `[v`]=")
  end)
end

M.buffer_enter_event = function(args)
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
  if hijack_netrw() then
    return
  end

  -- For all others, make sure another buffer is not hijacking our window
  -- ..but not if the position is "split"
  local prior_buf = vim.fn.bufnr("#")
  if prior_buf < 1 then
    return
  end
  local prior_type = vim.api.nvim_buf_get_option(prior_buf, "filetype")
  if prior_type == "neo-tree" then
    local position = vim.api.nvim_buf_get_var(prior_buf, "neo_tree_position")
    if position == "split" then
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
      if position ~= "split" then
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

--TODO: Remove the do_not_focus and close_others options in 2.0
M.show = function(source_name, do_not_focus, close_others, toggle_if_open)
  source_name = check_source(source_name)
  if get_position(source_name) == "split" then
    M.show_in_split(source_name, toggle_if_open)
    return
  end

  if toggle_if_open then
    if manager.close(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  if close_others == nil then
    close_others = true
  end
  if close_others then
    M.close_all_except(source_name)
  end
  if do_not_focus then
    manager.show(source_name)
  else
    manager.focus(source_name)
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

M.setup = function(config, is_auto_config)
  local default_config = vim.deepcopy(defaults)
  config = vim.deepcopy(config or {})
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
  local merged_source_config = {}
  for _, source_name in ipairs(sources) do
    local default_source_config = default_config[source_name]
    local mod_root = "neo-tree.sources." .. source_name
    default_source_config.components = require(mod_root .. ".components")
    default_source_config.commands = require(mod_root .. ".commands")
    default_source_config.name = source_name

    --validate the window.position
    local pos_key = source_name .. ".window.position"
    local position = utils.get_value(config, pos_key, "left", true)
    local valid_positions = {
      left = true,
      right = true,
      top = true,
      bottom = true,
      float = true,
      split = true,
    }
    if not valid_positions[position] then
      log.error("Invalid value for ", pos_key, ": ", position)
      config[source_name].window.position = "left"
    end

    -- Make sure all the mappings are normalized so they will merge properly.
    normalize_mappings(default_source_config)
    normalize_mappings(config[source_name])

    -- if user sets renderers, completely wipe the default ones
    for name, _ in pairs(default_source_config.renderers) do
      local user = utils.get_value(config, source_name .. ".renderers." .. name)
      if user then
        default_source_config.renderers[name] = nil
      end
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

  if not is_auto_config and get_hijack_netrw_behavior() ~= "disabled" then
    vim.cmd("silent! autocmd! FileExplorer *")
  end
end

M.show_logs = function()
  vim.cmd("tabnew " .. log.outfile)
end

ensure_config()
return M
