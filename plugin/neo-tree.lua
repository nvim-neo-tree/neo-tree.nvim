if vim.g.loaded_neo_tree == 1 or vim.g.loaded_neo_tree == true then
  return
end

-- Possibly convert this to lua using customlist instead of custom in the future?
vim.api.nvim_create_user_command("Neotree", function(ctx)
  require("neo-tree.command")._command(unpack(ctx.fargs))
end, {
  nargs = "*",
  complete = "custom,v:lua.require'neo-tree.command'.complete_args",
})

---@param path string? The path to check
---@return boolean hijacked Whether we hijacked a buffer
local function try_netrw_hijack(path)
  if not path or #path == 0 then
    return false
  end

  local stats = (vim.uv or vim.loop).fs_stat(path)
  if not stats or stats.type ~= "directory" then
    return false
  end

  return require("neo-tree.setup.netrw").hijack()
end

local augroup = vim.api.nvim_create_augroup("NeoTree", { clear = true })

-- lazy load until bufenter/netrw hijack
vim.api.nvim_create_autocmd({ "BufEnter" }, {
  group = augroup,
  desc = "Lazy-load until bufenter/opened dir",
  callback = function(args)
    return vim.g.neotree_watching_bufenter == 1 or try_netrw_hijack(args.file)
  end,
})

-- track window order
vim.api.nvim_create_autocmd({ "WinEnter" }, {
  group = augroup,
  desc = "Track prior windows for opening intuitiveness",
  callback = function(ev)
    local win = vim.api.nvim_get_current_win()
    local utils = require("neo-tree.utils")
    if utils.is_floating(win) then
      return
    end

    if vim.bo[ev.buf].filetype == "neo-tree" then
      return
    end

    local tabid = vim.api.nvim_get_current_tabpage()
    utils.prior_windows[tabid] = utils.prior_windows[tabid] or {}
    local tab_windows = utils.prior_windows[tabid]
    table.insert(tab_windows, win)

    -- prune history
    local win_count = #tab_windows
    if win_count > 100 then
      if table.move then
        utils.prior_windows[tabid] =
          require("neo-tree.utils._compat").table_move(tab_windows, 80, win_count, 1, {})
        return
      end

      local new_array = {}
      for i = 80, win_count do
        table.insert(new_array, tab_windows[i])
      end
      utils.prior_windows[tabid] = new_array
    end
  end,
})

-- setup session loading
vim.api.nvim_create_autocmd("SessionLoadPost", {
  group = augroup,
  desc = "Session loading",
  callback = function()
    if require("neo-tree").ensure_config().auto_clean_after_session_restore then
      require("neo-tree.ui.renderer").clean_invalid_neotree_buffers(true)
    end
  end,
})

vim.api.nvim_create_autocmd("WinClosed", {
  group = augroup,
  desc = "close_if_last_window autocmd",
  callback = function(args)
    local closing_win = tonumber(args.match)
    local visible_winids = vim.api.nvim_tabpage_list_wins(0)
    local other_panes = {}
    local utils = require("neo-tree.utils")
    for _, winid in ipairs(visible_winids) do
      if not utils.is_floating(winid) and winid ~= closing_win then
        other_panes[#other_panes + 1] = winid
      end
    end

    if #other_panes ~= 1 then
      return
    end

    local remaining_pane = other_panes[1]
    local remaining_buf = vim.api.nvim_win_get_buf(remaining_pane)

    if vim.bo[remaining_buf].filetype ~= "neo-tree" then
      return
    end

    local position = vim.b[remaining_buf].neo_tree_position
    local source = vim.b[remaining_buf].neo_tree_source
    -- close_if_last_window just doesn't make sense for a split style
    if position == "current" then
      return
    end

    local log = require("neo-tree.log")
    log.trace("last window, closing")
    local state = require("neo-tree.sources.manager").get_state(source)
    if not state then
      return
    end
    if not require("neo-tree").ensure_config().close_if_last_window then
      return
    end
    local mod = utils.get_opened_buffers()
    log.debug("close_if_last_window, modified files found:", vim.inspect(mod))
    for filename, buf_info in pairs(mod) do
      if buf_info.modified then
        local buf_name, message
        if vim.startswith(filename, "[No Name]#") then
          buf_name = string.sub(filename, 11)
          message =
            "Cannot close because an unnamed buffer is modified. Please save or discard this file."
        else
          buf_name = filename
          message =
            "Cannot close because one of the files is modified. Please save or discard changes."
        end
        log.trace("close_if_last_window, showing unnamed modified buffer:", filename)
        vim.schedule(function()
          log.warn(message)
          vim.cmd("rightbelow vertical split")
          vim.api.nvim_win_set_width(0, state.window.width or 40)
          vim.cmd("b " .. buf_name)
        end)
        return
      end
    end
    -- this needs to be scheduled, otherwise VimLeavePre autocmds won't trigger
    vim.schedule(function()
      vim.cmd("q!")
    end)
  end,
})

vim.g.loaded_neo_tree = 1
