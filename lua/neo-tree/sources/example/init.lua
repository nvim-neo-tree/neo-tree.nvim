--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")

local M = { name = "example" }

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(state, path)
  if path == nil then
    path = vim.fn.getcwd()
  end
  state.path = path

  -- Do something useful here to get items
  local items = {
    {
      id = "1",
      name = "root",
      children = {
        {
          id = "1.1",
          name = "child1",
          children = {
            {
              id = "1.1.1",
              name = "child1.1",
            },
            {
              id = "1.1.2",
              name = "child1.2",
            },
          },
        },
      },
    },
  }
  renderer.show_nodes(state, items)
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  -- You most likely want to use this function to subscribe to events
  manager.subscribe(M.name, {
    event = events.FS_EVENT,
    handler = function(args)
      M.navigate()
    end,
  })
end

return M
