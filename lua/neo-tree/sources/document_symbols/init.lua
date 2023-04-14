--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local symbols = require("neo-tree.sources.document_symbols.lib.symbols_utils")

local M = { name = "document_symbols" }

local get_state = function()
  return manager.get_state(M.name)
end

local refresh_debounced = function(args)
  if utils.is_real_file(args.afile) == false then
    return
  end
  utils.debounce(
    "document_symbols_refresh",
    utils.wrap(manager.refresh, M.name),
    100,
    utils.debounce_strategy.CALL_LAST_ONLY
  )
end

---Navigate to the given path.
M.navigate = function(state)
  state.lsp_winid, _ = utils.get_appropriate_window(state)
  state.lsp_bufnr = vim.api.nvim_win_get_buf(state.lsp_winid)
  state.path = vim.api.nvim_buf_get_name(state.lsp_bufnr)

  symbols.render_symbols(state)
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
---wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  symbols.setup(config)

  if config.before_render then
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

  local refresh_events = {
    events.VIM_BUFFER_ENTER,
    events.VIM_INSERT_LEAVE,
    events.VIM_TEXT_CHANGED_NORMAL,
  }
  for _, event in ipairs(refresh_events) do
    manager.subscribe(M.name, {
      event = event,
      handler = refresh_debounced,
    })
  end
end

return M
