--This file should have all functions that are in the public api and either set
--or read the state of this source.

local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local symbols = require("neo-tree.sources.document_symbols.lib.symbols_utils")
local renderer = require("neo-tree.ui.renderer")

---@class neotree.sources.DocumentSymbols : neotree.Source
local M = {
  name = "document_symbols",
  display_name = "  Symbols ",
}

local get_state = function()
  return manager.get_state(M.name)
end

---Returns the state for this source in the current tab if it is actually open,
---without creating a new state.
---@return neotree.StateWithTree? state
local get_active_state = function()
  local tabid = vim.api.nvim_get_current_tabpage()
  for _, state in ipairs(manager._get_all_states()) do
    if state.name == M.name and state.tabid == tabid and renderer.window_exists(state) then
      return state --[[@as neotree.StateWithTree]]
    end
  end
  return nil
end

---Syncs the lsp window to the window the cursor is currently in, if it is a
---suitable window to show symbols for. Does nothing if the current window is
---the neo-tree window, a floating window, or does not contain a real file.
---@param state neotree.StateWithTree
local sync_lsp_window = function(state)
  local winid = vim.api.nvim_get_current_win()
  if winid == state.winid then
    return
  end
  if utils.is_floating(winid) then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if vim.bo[bufnr].filetype == "neo-tree" then
    return
  end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if not utils.is_real_file(bufname) then
    return
  end
  state.lsp_winid = winid
  state.lsp_bufnr = bufnr
  state.path = bufname
end

---Refresh the source with debouncing
---@param args { afile: string }
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

---Internal function to follow the cursor
local follow_symbol = function()
  local state = get_state()
  if state.lsp_bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end
  if not (state.lsp_winid and vim.api.nvim_win_is_valid(state.lsp_winid)) then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(state.lsp_winid)
  local node_id = symbols.get_symbol_by_loc(state.tree, { cursor[1] - 1, cursor[2] })
  if #node_id > 0 then
    renderer.focus_node(state, node_id, true)
  end
end

---@class neotree.sources.documentsymbols.DebounceArgs

---Follow the cursor with debouncing
---@param args { afile: string }
local follow_debounced = function(args)
  if utils.is_real_file(args.afile) == false then
    return
  end
  utils.debounce(
    "document_symbols_follow",
    utils.wrap(follow_symbol, args.afile),
    100,
    utils.debounce_strategy.CALL_LAST_ONLY
  )
end

---Navigate to the given path.
M.navigate = function(state, path, path_to_reveal, callback, async)
  sync_lsp_window(state)
  if not (state.lsp_winid and vim.api.nvim_win_is_valid(state.lsp_winid)) then
    state.lsp_winid, _ = utils.get_appropriate_window(state)
    state.lsp_bufnr = vim.api.nvim_win_get_buf(state.lsp_winid)
    state.path = vim.api.nvim_buf_get_name(state.lsp_bufnr)
  end

  symbols.render_symbols(state, callback)
end

---@class neotree.Config.LspKindDisplay
---@field icon string
---@field hl string

---@class neotree.Config.DocumentSymbols.Renderers : neotree.Config.Renderers
---@field root neotree.Component.DocumentSymbols[]?
---@field symbol neotree.Component.DocumentSymbols[]?

---@class (exact) neotree.Config.DocumentSymbols : neotree.Config.Source
---@field follow_cursor boolean?
---@field follow_tree_cursor boolean?
---@field client_filters neotree.lsp.ClientFilter?
---@field custom_kinds table<integer, string>?
---@field kinds table<string, neotree.Config.LspKindDisplay>?
---@field renderers neotree.Config.DocumentSymbols.Renderers?

---Configures the plugin, should be called before the plugin is used.
---@param config neotree.Config.DocumentSymbols
---@param global_config neotree.Config.Base
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

  -- Keep the lsp window synced with the window the cursor is in, so that
  -- jumping to symbols and following the cursor work after splitting or
  -- moving between windows with <C-w>.
  manager.subscribe(M.name, {
    event = events.VIM_WIN_ENTER,
    handler = function()
      local state = get_active_state()
      if state then
        sync_lsp_window(state)
      end
    end,
  })
  manager.subscribe(M.name, {
    event = events.VIM_WIN_CLOSED,
    handler = function(args)
      local state = get_active_state()
      if not state then
        return
      end
      local closed_winid = tonumber(args.afile) or tonumber(args.match)
      if closed_winid and closed_winid == state.lsp_winid then
        -- The window we were tracking is gone, clear it so that consumers
        -- can fall back to deriving a new one.
        state.lsp_winid = nil
        state.lsp_bufnr = nil
      end
    end,
  })

  if config.follow_cursor then
    manager.subscribe(M.name, {
      event = events.VIM_CURSOR_MOVED,
      handler = follow_debounced,
    })
    manager.subscribe(M.name, {
      event = events.AFTER_RENDER,
      handler = function(state)
        follow_debounced({ afile = vim.api.nvim_buf_get_name(0) })
      end,
    })
  end

  -- Set up follow_tree_cursor: show symbol on cursor move in document_symbols buffer
  if config.follow_tree_cursor then
    manager.subscribe(M.name, {
      event = events.NEO_TREE_BUFFER_ENTER,
      handler = function()
        local bufnr = vim.api.nvim_get_current_buf()
        -- Only set up for document_symbols source
        local state = manager.get_state("document_symbols")
        if not state or state.bufnr ~= bufnr then
          return
        end
        local group = vim.api.nvim_create_augroup(
          "neo_tree_document_symbols_follow_tree_cursor",
          { clear = true }
        )
        vim.api.nvim_create_autocmd("CursorMoved", {
          group = group,
          buffer = bufnr,
          callback = function()
            local current_state = manager.get_state("document_symbols")
            if not current_state or not current_state.tree then
              return
            end
            -- Verify we're still in the right buffer
            if vim.api.nvim_get_current_buf() ~= current_state.bufnr then
              return
            end
            local commands = require("neo-tree.sources.document_symbols.commands")
            commands.show_symbol(current_state)
          end,
        })
      end,
    })
  end
end

return M
