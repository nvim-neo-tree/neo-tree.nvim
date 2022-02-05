--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local items = require("neo-tree.sources.git_status.lib.items")
local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")

local M = { name = "git_status" }

local wrap = function(func)
  return utils.wrap(func, M.name)
end

local get_state = function()
  return manager.get_state(M.name)
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(state, path)
  state.dirty = false
  items.get_git_status(state)
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
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
  end

  manager.subscribe(M.name, {
    event = events.VIM_BUFFER_CHANGED,
    handler = wrap(manager.refresh),
  })

  if config.bind_to_cwd then
    manager.subscribe(M.name, {
      event = events.VIM_DIR_CHANGED,
      handler = wrap(manager.refresh),
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
