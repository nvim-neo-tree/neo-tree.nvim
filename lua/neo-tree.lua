local M = {}

--- To be removed in a future release, use this instead:
--- ```lua
--- require("neo-tree.command").execute({ action = "close" })
--- ```
---@deprecated
M.close_all = function()
  require("neo-tree.command").execute({ action = "close" })
end

---@type neotree.Config?
local new_user_config = nil

---Updates the config of neo-tree using the latest user config passed through setup, if any.
---@return neotree.Config.Base
M.ensure_config = function()
  if not M.config or new_user_config then
    M.config = require("neo-tree.setup").merge_config(new_user_config)
    new_user_config = nil
  end
  return M.config
end

---@param ignore_filetypes string[]?
---@param ignore_winfixbuf boolean?
M.get_prior_window = function(ignore_filetypes, ignore_winfixbuf)
  local utils = require("neo-tree.utils")
  ignore_filetypes = ignore_filetypes or {}
  local ignore = utils.list_to_dict(ignore_filetypes)
  ignore["neo-tree"] = true

  local tabid = vim.api.nvim_get_current_tabpage()
  local wins = utils.prior_windows[tabid]
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
        local ft = vim.bo[buf].filetype
        local bt = vim.bo[buf].buftype or "normal"
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
  local utils = require("neo-tree.utils")
  ---@type string
  local base_path = assert(debug.getinfo(utils.truthy).source:match("@(.*)/utils/init.lua$"))
  ---@type string
  local config_path = base_path .. utils.path_separator .. "defaults.lua"
  ---@type string[]?
  local lines = vim.fn.readfile(config_path)
  if lines == nil then
    error("Could not read neo-tree.defaults")
  end

  -- read up to the end of the config, jut to omit the final return
  ---@type string[]
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
  require("neo-tree.log").set_level(level)
end

---Ideally this should only be in plugin/neo-tree.lua but lazy-loading might mean this runs before bufenter
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

---@param config neotree.Config
M.setup = function(config)
  -- merging is deferred until ensure_config
  new_user_config = config
  if vim.v.vim_did_enter == 0 then
    try_netrw_hijack(vim.fn.argv(0) --[[@as string]])
  end
end

M.show_logs = function()
  vim.cmd("tabnew " .. require("neo-tree.log").outfile)
end

return M
