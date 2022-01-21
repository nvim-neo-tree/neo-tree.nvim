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
    M.setup({ log_to_file = false })
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
  end)

  events.define_autocmd_event(events.VIM_BUFFER_CHANGED, { "BufWritePost", "BufFilePost" }, 200)
  events.define_autocmd_event(events.VIM_BUFFER_ADDED, { "BufAdd" }, 200)
  events.define_autocmd_event(events.VIM_BUFFER_DELETED, { "BufDelete" }, 200)
  events.define_autocmd_event(events.VIM_BUFFER_ENTER, { "BufEnter", "BufWinEnter" }, 0)
  events.define_autocmd_event(events.VIM_WIN_ENTER, { "WinEnter" }, 0)
  events.define_autocmd_event(events.VIM_DIR_CHANGED, { "DirChanged" }, 200)
  events.define_autocmd_event(events.VIM_TAB_CLOSED, { "TabClosed" })

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

M.close_all_except = function(source_name)
  source_name = check_source(source_name)
  local target_pos = utils.get_value(M, "config." .. source_name .. ".window.position", "left")
  for _, name in ipairs(sources) do
    if name ~= source_name then
      local pos = utils.get_value(M, "config." .. name .. ".window.position", "left")
      if pos == target_pos then
        manager.close(source_name)
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
      local pos = utils.get_value(M, "config." .. name .. ".window.position", "left")
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

M.reveal_current_file = function(source_name, toggle_if_open)
  source_name = check_source(source_name)
  if toggle_if_open then
    if manager.close(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  manager.reveal_current_file(source_name)
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

M.win_enter_event = function()
  local win_id = vim.api.nvim_get_current_win()
  if utils.is_floating(win_id) then
    return
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

M.setup = function(config)
  config = config or {}
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
    handler = function(args)
      if utils.is_floating() then
        return
      end
      local prior_buf = vim.fn.bufnr("#")
      if prior_buf < 1 then
        return
      end
      local prior_type = vim.api.nvim_buf_get_option(prior_buf, "filetype")
      if prior_type == "neo-tree" and vim.bo.filetype ~= "neo-tree" then
        local bufname = vim.fn.bufname()
        vim.cmd("b#")
        -- Using schedule at this point  fixes problem with syntax
        -- highlighting in the buffer. I also prevents errors with diagnostics
        -- trying to work with gthe buffer as it's being closed.
        vim.schedule(function()
          -- try to delete the buffer, only because if it was new it would take
          -- on options from the neo-tree window that are undesirable.
          pcall(vim.cmd, "bdelete " .. bufname)
          local fake_state = {
            window = {
              position = "left",
            },
          }
          utils.open_file(fake_state, bufname)
        end)
      end
    end,
  })

  if config.event_handlers ~= nil then
    for _, handler in ipairs(config.event_handlers) do
      events.subscribe(handler)
    end
  end

  highlights.setup()

  -- setup the default values for all sources
  local source_defaults = {}
  for _, source_name in ipairs(sources) do
    local mod_root = "neo-tree.sources." .. source_name
    local source = require(mod_root .. ".defaults")
    source.components = require(mod_root .. ".components")
    source.commands = require(mod_root .. ".commands")
    source.name = source_name

    -- Make sure all the mappings are normalized so they will merge properly.
    normalize_mappings(source)
    normalize_mappings(config[source_name])

    -- if user sets renderers, completely wipe the default ones
    if utils.get_value(config, source_name .. ".renderers.directory") then
      source.renderers.directory = {}
    end
    if utils.get_value(config, source_name .. ".renderers.file") then
      source.renderers.file = {}
    end
    source_defaults[source_name] = source
  end
  local default_config = utils.table_merge(defaults, source_defaults)

  -- apply the users config
  M.config = utils.table_merge(default_config, config)

  -- setup the sources with the combined config
  for _, source_name in ipairs(sources) do
    manager.setup(source_name, M.config[source_name], M.config)
  end

  local event_handler = {
    event = events.VIM_WIN_ENTER,
    handler = M.win_enter_event,
    id = "neo-tree-win-enter",
  }
  if config.open_files_in_last_window then
    events.subscribe(event_handler)
  else
    events.unsubscribe(event_handler)
    config.prior_windows = nil
  end
end

M.show_logs = function()
  vim.cmd("tabnew " .. log.outfile)
end

ensure_config()
return M
