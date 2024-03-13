local vim = vim
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local M = {}

-- DEPRECATED: to be removed in a future release, use this instead:
-- ```
-- require("neo-tree.command").execute({ action = "close" })
-- ```
M.close_all = function()
  require("neo-tree.command").execute({ action = "close" })
end

M.ensure_config = function()
  if not M.config then
    M.setup({ log_to_file = false }, true)
  end
end

M.get_prior_window = function(ignore_filetypes, ignore_winfixbuf)
  ignore_filetypes = ignore_filetypes or {}
  local ignore = utils.list_to_dict(ignore_filetypes)
  ignore["neo-tree"] = true

  local tabid = vim.api.nvim_get_current_tabpage()
  local wins = utils.get_value(M, "config.prior_windows", {}, true)[tabid]
  if wins == nil then
    return -1
  end
  local win_index = #wins
  while win_index > 0 do
    local last_win = wins[win_index]
    if type(last_win) == "number" then
      local success, is_valid = pcall(vim.api.nvim_win_is_valid, last_win)
      if success and is_valid and not (ignore_winfixbuf and utils.is_winfixbuf(last_win)) then
        local buf = vim.api.nvim_win_get_buf(last_win)
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        local bt = vim.api.nvim_buf_get_option(buf, "buftype") or "normal"
        if ignore[ft] ~= true and ignore[bt] ~= true then
          return last_win
        end
      end
    end
    win_index = win_index - 1
  end
  return -1
end

M.paste_default_config = function()
  local base_path = debug.getinfo(utils.truthy).source:match("@(.*)/utils/init.lua$")
  local config_path = base_path .. utils.path_separator .. "defaults.lua"
  local lines = vim.fn.readfile(config_path)
  if lines == nil then
    error("Could not read neo-tree.defaults")
  end

  -- read up to the end of the config, jut to omit the final return
  local config = {}
  for _, line in ipairs(lines) do
    table.insert(config, line)
    if line == "}" then
      break
    end
  end

  vim.api.nvim_put(config, "l", true, false)
  vim.schedule(function()
    vim.cmd("normal! `[v`]=")
  end)
end

M.set_log_level = function(level)
  log.set_level(level)
end

M.setup = function(config, is_auto_config)
  M.config = require("neo-tree.setup").merge_config(config, is_auto_config)
  local netrw = require("neo-tree.setup.netrw")
  if not is_auto_config and netrw.get_hijack_netrw_behavior() ~= "disabled" then
    vim.cmd("silent! autocmd! FileExplorer *")
    netrw.hijack()
  end
end

M.show_logs = function()
  vim.cmd("tabnew " .. log.outfile)
end

return M
