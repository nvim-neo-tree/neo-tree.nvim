local uv = vim.uv or vim.loop
local nt = require("neo-tree")
local utils = require("neo-tree.utils")
local M = {}

local get_position = function(source_name)
  local pos = utils.get_value(nt.config, source_name .. ".window.position", "left", true)
  return pos
end

---@return neotree.Config.HijackNetrwBehavior
M.get_hijack_behavior = function()
  nt.ensure_config()
  return nt.config.filesystem.hijack_netrw_behavior
end

---@return boolean hijacked Whether the hijack was successful
M.hijack = function()
  local hijack_behavior = M.get_hijack_behavior()
  if hijack_behavior == "disabled" then
    return false
  end

  -- ensure this is a directory
  local dir_bufnr = vim.api.nvim_get_current_buf()
  local path_to_hijack = vim.api.nvim_buf_get_name(dir_bufnr)
  local stats = uv.fs_stat(path_to_hijack)
  if not stats or stats.type ~= "directory" then
    return false
  end

  -- record where we are now
  local pos = get_position("filesystem")
  local should_open_current = hijack_behavior == "open_current" or pos == "current"
  local dir_window = vim.api.nvim_get_current_win()

  -- Now actually open the tree, with a very quick debounce because this may be
  -- called multiple times in quick succession.
  utils.debounce("hijack_netrw_" .. dir_window, function()
    local manager = require("neo-tree.sources.manager")
    local log = require("neo-tree.log")
    -- We will want to replace the "directory" buffer with either the "alternate"
    -- buffer or a new blank one.
    local replacement_buffer = vim.fn.bufnr("#")
    local is_currently_neo_tree = false
    if replacement_buffer > 0 then
      if vim.bo[replacement_buffer].filetype == "neo-tree" then
        -- don't hijack the current window if it's already a Neo-tree sidebar
        local position = vim.b[replacement_buffer].neo_tree_position
        if position == "current" then
          replacement_buffer = -1
        else
          is_currently_neo_tree = true
        end
      end
    end
    if not should_open_current then
      if replacement_buffer == dir_bufnr or replacement_buffer < 1 then
        replacement_buffer = vim.api.nvim_create_buf(true, false)
        log.trace("Created new buffer for netrw hijack", replacement_buffer)
      end
    end
    if replacement_buffer > 0 then
      log.trace("Replacing buffer in netrw hijack", replacement_buffer)
      pcall(vim.api.nvim_win_set_buf, dir_window, replacement_buffer)
    end

    -- If a window takes focus (e.g. lazy.nvim installing plugins on startup) in the time between the method call and
    -- this debounced callback, we should focus that window over neo-tree.
    local current_window = vim.api.nvim_get_current_win()
    local should_restore_cursor = current_window ~= dir_window

    local cleanup = vim.schedule_wrap(function()
      log.trace("Deleting buffer in netrw hijack", dir_bufnr)
      pcall(vim.api.nvim_buf_delete, dir_bufnr, { force = true })
      if should_restore_cursor then
        vim.api.nvim_set_current_win(current_window)
      end
    end)

    ---@type neotree.sources.filesystem.State
    local state
    if should_open_current and not is_currently_neo_tree then
      log.debug("hijack_netrw: opening current")
      state = manager.get_state("filesystem", nil, dir_window) --[[@as neotree.sources.filesystem.State]]
      state.current_position = "current"
    elseif is_currently_neo_tree then
      log.debug("hijack_netrw: opening in existing Neo-tree")
      state = manager.get_state("filesystem") --[[@as neotree.sources.filesystem.State]]
    else
      log.debug("hijack_netrw: opening default")
      manager.close_all_except("filesystem")
      state = manager.get_state("filesystem") --[[@as neotree.sources.filesystem.State]]
    end

    require("neo-tree.sources.filesystem")._navigate_internal(state, path_to_hijack, nil, cleanup)
  end, 10, utils.debounce_strategy.CALL_LAST_ONLY)

  return true
end

return M
