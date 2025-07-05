local q = require("neo-tree.events.queue")
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")

---@class neotree.event.Functions
local M = {
  -- Well known event names, you can make up your own
  AFTER_RENDER = "after_render",
  BEFORE_FILE_ADD = "before_file_add",
  BEFORE_FILE_DELETE = "before_file_delete",
  BEFORE_FILE_MOVE = "before_file_move",
  BEFORE_FILE_RENAME = "before_file_rename",
  BEFORE_RENDER = "before_render",
  FILE_ADDED = "file_added",
  FILE_DELETED = "file_deleted",
  FILE_MOVED = "file_moved",
  FILE_OPENED = "file_opened",
  FILE_OPEN_REQUESTED = "file_open_requested",
  FILE_RENAMED = "file_renamed",
  FS_EVENT = "fs_event",
  GIT_EVENT = "git_event",
  GIT_STATUS_CHANGED = "git_status_changed",
  STATE_CREATED = "state_created",
  NEO_TREE_BUFFER_ENTER = "neo_tree_buffer_enter",
  NEO_TREE_BUFFER_LEAVE = "neo_tree_buffer_leave",
  NEO_TREE_LSP_UPDATE = "neo_tree_lsp_update",
  NEO_TREE_POPUP_BUFFER_ENTER = "neo_tree_popup_buffer_enter",
  NEO_TREE_POPUP_BUFFER_LEAVE = "neo_tree_popup_buffer_leave",
  NEO_TREE_POPUP_INPUT_READY = "neo_tree_popup_input_ready",
  NEO_TREE_WINDOW_AFTER_CLOSE = "neo_tree_window_after_close",
  NEO_TREE_WINDOW_AFTER_OPEN = "neo_tree_window_after_open",
  NEO_TREE_WINDOW_BEFORE_CLOSE = "neo_tree_window_before_close",
  NEO_TREE_WINDOW_BEFORE_OPEN = "neo_tree_window_before_open",
  NEO_TREE_PREVIEW_BEFORE_RENDER = "neo_tree_preview_before_render",
  VIM_AFTER_SESSION_LOAD = "vim_after_session_load",
  VIM_BUFFER_ADDED = "vim_buffer_added",
  VIM_BUFFER_CHANGED = "vim_buffer_changed",
  VIM_BUFFER_DELETED = "vim_buffer_deleted",
  VIM_BUFFER_ENTER = "vim_buffer_enter",
  VIM_BUFFER_MODIFIED_SET = "vim_buffer_modified_set",
  VIM_COLORSCHEME = "vim_colorscheme",
  VIM_CURSOR_MOVED = "vim_cursor_moved",
  VIM_DIAGNOSTIC_CHANGED = "vim_diagnostic_changed",
  VIM_DIR_CHANGED = "vim_dir_changed",
  VIM_INSERT_LEAVE = "vim_insert_leave",
  VIM_LEAVE = "vim_leave",
  VIM_LSP_REQUEST = "vim_lsp_request",
  VIM_RESIZED = "vim_resized",
  VIM_TAB_CLOSED = "vim_tab_closed",
  VIM_TERMINAL_ENTER = "vim_terminal_enter",
  VIM_TEXT_CHANGED_NORMAL = "vim_text_changed_normal",
  VIM_WIN_CLOSED = "vim_win_closed",
  VIM_WIN_ENTER = "vim_win_enter",
}

---@param autocmds string
---@return string event
---@return string? pattern
local parse_autocmd_string = function(autocmds)
  local parsed = vim.split(autocmds, " ")
  return parsed[1], parsed[2]
end

---@param event_name neotree.EventName|string
---@param autocmds string[]
---@param debounce_frequency integer?
---@param seed_fn function?
---@param nested boolean?
M.define_autocmd_event = function(event_name, autocmds, debounce_frequency, seed_fn, nested)
  log.debug("Defining autocmd event: %s", event_name)
  local augroup_name = "NeoTreeEvent_" .. event_name
  q.define_event(event_name, {
    setup = function()
      local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = false })
      for _, autocmd in ipairs(autocmds) do
        local event, pattern = parse_autocmd_string(autocmd)
        log.trace("Registering autocmds on %s %s", event, pattern or "")
        vim.api.nvim_create_autocmd({ event }, {
          pattern = pattern or "*",
          group = augroup,
          nested = nested,
          callback = function(args)
            ---@class neotree.event.Autocmd.CallbackArgs : neotree._vim.api.keyset.create_autocmd.callback_args
            ---@field afile string
            local event_args = args --[[@as neotree._vim.api.keyset.create_autocmd.callback_args]]
            event_args.afile = args.file or ""
            M.fire_event(event_name, event_args)
          end,
        })
      end
    end,
    seed = seed_fn,
    teardown = function()
      log.trace("Teardown autocmds for ", event_name)
      vim.api.nvim_create_augroup(augroup_name, { clear = true })
    end,
    debounce_frequency = debounce_frequency,
    debounce_strategy = utils.debounce_strategy.CALL_LAST_ONLY,
  })
end

M.clear_all_events = q.clear_all_events
M.define_event = q.define_event
M.destroy_event = q.destroy_event
M.fire_event = q.fire_event

M.subscribe = q.subscribe
M.unsubscribe = q.unsubscribe

return M
