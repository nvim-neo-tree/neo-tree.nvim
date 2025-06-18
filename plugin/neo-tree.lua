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

local augroup = vim.api.nvim_create_augroup("NeoTree_NetrwDeferred", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter" }, {
  group = augroup,
  callback = function(args)
    return vim.g.neotree_watching_bufenter == 1 or try_netrw_hijack(args.file)
  end,
})

vim.api.nvim_create_autocmd({ "WinEnter" }, {
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
        utils.prior_windows[tabid] = table.move(tab_windows, 80, win_count, 1, {})
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

vim.g.loaded_neo_tree = 1
