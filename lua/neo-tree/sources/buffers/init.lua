--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local items = require("neo-tree.sources.buffers.lib.items")
local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")
local git = require("neo-tree.git")

local M = { name = "buffers" }

local wrap = function(func)
  return utils.wrap(func, M.name)
end

local get_state = function()
  return manager.get_state(M.name)
end

local buffers_changed_internal = function()
  for _, tabnr in ipairs(vim.api.nvim_list_tabpages()) do
    local state = manager.get_state(M.name, tabnr)
    if state.path and renderer.window_exists(state) then
      items.get_open_buffers(state)
    end
  end
end

---Calld by autocmd when any buffer is open, closed, renamed, etc.
M.buffers_changed = function()
  utils.debounce(
    "buffers_changed",
    buffers_changed_internal,
    500,
    utils.debounce_strategy.CALL_LAST_ONLY
  )
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(state, path)
  state.dirty = false
  local path_changed = false
  if path == nil then
    path = vim.fn.getcwd()
  end
  if path ~= state.path then
    state.path = path
    path_changed = true
  end

  items.get_open_buffers(state)

  if path_changed and state.bind_to_cwd then
    vim.api.nvim_command("tcd " .. path)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  --Configure events for before_render
  if config.before_render then
    --convert to new event system
    manager.subscribe(M.name, {
      event = events.BEFORE_RENDER,
      handler = function(state)
        local this_state = get_state()
        if state == this_state then
          config.before_render(this_state)
        end
      end,
    })
  elseif global_config.enable_git_status then
    manager.subscribe(M.name, {
      event = events.BEFORE_RENDER,
      handler = function(state)
        local this_state = get_state()
        if state == this_state then
          state.git_status_lookup = git.status()
        end
      end,
    })
  end

  local refresh_events = {
    events.VIM_BUFFER_CHANGED,
    events.VIM_BUFFER_ADDED,
    events.VIM_BUFFER_DELETED,
  }
  for _, e in ipairs(refresh_events) do
    manager.subscribe(M.name, {
      event = e,
      handler = M.buffers_changed,
    })
  end

  if config.bind_to_cwd then
    manager.subscribe(M.name, {
      event = events.VIM_DIR_CHANGED,
      handler = wrap(manager.dir_changed),
    })
  end

  if global_config.enable_diagnostics then
    manager.subscribe(M.name, {
      event = events.VIM_DIAGNOSTIC_CHANGED,
      handler = wrap(manager.diagnostics_changed),
    })
  end
end

return M
