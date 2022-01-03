--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local inputs   = require("neo-tree.ui.inputs")

local M = {}
local default_config = nil
local state_by_tab = {}

local get_state = function()
  local tabnr = vim.api.nvim_get_current_tabpage()
  local state = state_by_tab[tabnr]
  if not state then
    state = utils.table_copy(default_config)
    state.tabnr = tabnr
    state_by_tab[tabnr] = state
  end
  return state
end

local expand_to_root
expand_to_root = function(tree, from_node)
  local parent_id = from_node:get_parent_id()
  if not parent_id then
    return
  end
  local parent_node = tree:get_node(parent_id)
  if parent_node then
    parent_node:expand()
    expand_to_root(tree, parent_node)
  end
end

local reveal_file = function(path)
  if not path then
    return nil
  end
  local state = get_state()
  local tree = state.tree
  if not tree then
    return false
  end
  local node = tree:get_node(path)
  if not node then
    return false
  end
  --expand_to_root(tree, node)
  --tree:render()

  local lines = vim.api.nvim_buf_line_count(state.bufnr)
  local linenr = 0
  while linenr < lines do
    linenr = linenr + 1
    node = tree:get_node(linenr)
    if node then
      if node:get_id() == path then
        local col = 0
        if node.indent then
          col = string.len(node.indent)
        end
        vim.api.nvim_set_current_win(state.split.winid)
        vim.api.nvim_win_set_cursor(state.split.winid, { linenr, col })
        return true
      end
    else
      --must be out of nodes
      return false
    end
  end
  return false
end

M.close = function()
  local state = get_state()
  renderer.close(state)
end

---Called by autocmds when the cwd dir is changed. This will change the root.
M.dir_changed = function()
  local state = get_state()
  local cwd = vim.fn.getcwd()
  if state.path and cwd == state.path then
    return
  end
  if state.path and renderer.window_exists(state) then
    M.navigate(cwd)
  end
end

---Focus the window, opening it if it is not already open.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.focus = function(path_to_reveal, callback)
  local state = get_state()
  if path_to_reveal then
    M.navigate(state.path, path_to_reveal, callback)
  else
    if renderer.window_exists(state) then
      vim.api.nvim_set_current_win(state.split.winid)
    else
      M.navigate(state.path, nil, callback)
    end
  end
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.navigate = function(path, path_to_reveal, callback)
  local state = get_state()
  local path_changed = false
  if path == nil then
    path = vim.fn.getcwd()
  end
  if path ~= state.path then
    state.path = path
    path_changed = true
  end

  if path_to_reveal then
    fs_scan.get_items_async(state, nil, path_to_reveal, function()
      local found = reveal_file(path_to_reveal)
      if not found then
        print("Could not find " .. path_to_reveal)
      end
      if callback then
        callback()
      end
    end)
  else
    fs_scan.get_items_async(state, nil, nil, callback)
  end

  if path_changed and state.bind_to_cwd then
    vim.api.nvim_command("tcd " .. path)
  end
end


M.reveal_current_file = function()
  local path = vim.fn.expand("%:p")
  if not path or path == "" or path:match("term://") then
    M.focus()
    return
  end
  local state = get_state()
  local cwd = state.path
  if cwd == nil then
    cwd = vim.fn.getcwd()
  end
  if string.sub(path, 1, string.len(cwd)) ~= cwd then
    cwd, _ = utils.split_path(path)
    inputs.confirm("File not in cwd. Change cwd to " .. cwd .. "?", function(response)
      if response == true then
        state.path = cwd
        M.focus(path)
      end
    end)
    return
  end
  if path then
    if not reveal_file(path) then
      M.focus(path)
    end
  end
end


M.reset_search = function(refresh)
  if refresh == nil then
    refresh = true
  end
  local state = get_state()
  renderer.set_expanded_nodes(state.tree, state.open_folders_before_search)
  state.open_folders_before_search = nil
  state.search_pattern = nil
  if refresh then
    M.refresh()
  end
end

M.show_new_children = function(node)
  local state = get_state()
  if not node then
    node = state.tree:get_node()
  end
  if node.type ~= 'directory' then
    return
  end

  if node:is_expanded() then
    M.refresh()
  else
    fs_scan.get_items_async(state, nil, false, function()
      local new_node = state.tree:get_node(node:get_id())
      M.toggle_directory(new_node)
    end)
  end
end

---Redraws the tree without scanning the filesystem again. Use this after
-- making changes to the nodes that would affect how their components are
-- rendered.
M.redraw = function()
  local state = get_state()
  if renderer.window_exists(state) then
    state.tree:render()
  end
end

---Refreshes the tree by scanning the filesystem again.
M.refresh = function()
  local state = get_state()
  if state.path and renderer.window_exists(state) then
    M.navigate(state.path)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config)
  if default_config == nil then
    default_config = config
    local autocmds = {}
    local refresh_cmd = ":lua require('neo-tree.sources.filesystem').refresh()"
    table.insert(autocmds, "augroup neotreefilesystem")
    table.insert(autocmds, "autocmd!")
    table.insert(autocmds, "autocmd BufWritePost * " .. refresh_cmd)
    table.insert(autocmds, "autocmd BufDelete * " .. refresh_cmd)
    if default_config.bind_to_cwd then
      table.insert(autocmds, "autocmd DirChanged * :lua require('neo-tree.sources.filesystem').dir_changed()")
    end
    table.insert(autocmds, "augroup END")
    vim.cmd(table.concat(autocmds, "\n"))
  end
end

---Opens the tree and displays the current path or cwd.
---@param callback function Callback to call after the items are loaded.
M.show = function(callback)
  local state = get_state()
  M.navigate(state.path, nil, callback)
end

---Expands or collapses the current node.
M.toggle_directory = function (node)
  local state = get_state()
  local tree = state.tree
  if not node then
    node = tree:get_node()
  end
  if node.type ~= 'directory' then
    return
  end
  if node.loaded == false then
    fs_scan.get_items_async(state, node.id, true)
  elseif node:has_children() then
    local updated = false
    if node:is_expanded() then
      updated = node:collapse()
    else
      updated = node:expand()
    end
    if updated then
      tree:render()
    else
      tree:render()
    end
  end
end

return M
