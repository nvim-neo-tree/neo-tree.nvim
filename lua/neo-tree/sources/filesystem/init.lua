--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local inputs = require("neo-tree.ui.inputs")

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

local get_path_to_reveal = function()
  if vim.bo.filetype == "neo-tree" then
    return nil
  end
  local path = vim.fn.expand("%:p")
  if not path or path == "" or path:match("term://") then
    return nil
  end
  return path
end

M.close = function()
  local state = get_state()
  return renderer.close(state)
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

M.float = function()
  local state = get_state()
  state.force_float = true
  local path_to_reveal = get_path_to_reveal()
  M.navigate(state.path, path_to_reveal)
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
      vim.api.nvim_set_current_win(state.winid)
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
  local pos = utils.get_value(state, "window.position", "left")
  local was_float = state.force_float or pos == "float"
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
      renderer.focus_node(state, path_to_reveal)
      if callback then
        callback()
      end
    end)
  else
    local previously_focused = nil
    if state.tree and renderer.is_window_valid(state.winid) then
      local node = state.tree:get_node()
      if node then
        -- keep the current node selected
        previously_focused = node:get_id()
      end
    end
    fs_scan.get_items_async(state, nil, nil, function()
      local current_winid = vim.api.nvim_get_current_win()
      if path_changed and current_winid == state.winid and previously_focused then
        local currently_focused = state.tree:get_node():get_id()
        if currently_focused ~= previously_focused then
          renderer.focus_node(state, previously_focused, false)
        end
      end
      if callback then
        callback()
      end
    end)
  end

  if path_changed and state.bind_to_cwd then
    vim.api.nvim_command("tcd " .. path)
  end
end

M.reveal_current_file = function(toggle_if_open)
  if toggle_if_open then
    if M.close() then
      -- It was open, and now it's not.
      return
    end
  end
  local state = get_state()
  require("neo-tree").close_all_except("filesystem")
  local path = get_path_to_reveal()
  if not path then
    M.focus()
    return
  end
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
    if not renderer.focus_node(state, path) then
      M.focus(path)
    end
  end
end

M.reset_search = function(refresh)
  if refresh == nil then
    refresh = true
  end
  local state = get_state()
  if state.open_folders_before_search then
    renderer.set_expanded_nodes(state.tree, state.open_folders_before_search)
    state.open_folders_before_search = nil
  end
  state.search_pattern = nil
  if refresh then
    M.refresh()
  end
end

M.show_new_children = function(node_or_path)
  local state = get_state()
  local node = node_or_path
  if node_or_path == nil then
    node = state.tree:get_node()
  elseif type(node_or_path) == "string" then
    node = state.tree:get_node(node_or_path)
    if node == nil then
      local parent_path, _ = utils.split_path(node_or_path)
      node = state.tree:get_node(parent_path)
    end
  else
    node = node_or_path
  end

  if node.type ~= "directory" then
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

---Refresh the tree, but not more often than frequency_in_ms
---@param frequency_in_ms number The minimum time between refreshes.
M.refresh_debounced = function(frequency_in_ms)
  frequency_in_ms = frequency_in_ms or 500
  utils.debounce("filesystem_refresh", M.refresh, frequency_in_ms)
end

---Refreshes the tree by scanning the filesystem again.
M.refresh = function(callback)
  local state = get_state()
  if state.path and renderer.window_exists(state) then
    if type(callback) ~= "function" then
      callback = nil
    end
    M.navigate(state.path, nil, callback)
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config)
  if default_config == nil then
    default_config = config
    local autocmds = {}
    local refresh_cmd = ":lua require('neo-tree.sources.filesystem').refresh_debounced()"
    table.insert(autocmds, "augroup neotreefilesystem")
    table.insert(autocmds, "autocmd!")
    table.insert(autocmds, "autocmd BufWritePost * " .. refresh_cmd)
    table.insert(autocmds, "autocmd BufDelete * " .. refresh_cmd)
    if default_config.bind_to_cwd then
      table.insert(autocmds, "autocmd DirChanged * :lua require('neo-tree.sources.filesystem').dir_changed()")
    end
    table.insert(
      autocmds,
      string.format(
        [[
    if has('nvim-0.6')
      " Use the new diagnostic subsystem for neovim 0.6 and up
      au DiagnosticChanged * %s
    else
      au User LspDiagnosticsChanged * %s
    endif]],
        refresh_cmd,
        refresh_cmd
      )
    )
    table.insert(autocmds, "augroup END")
    local cmds = table.concat(autocmds, "\n")
    vim.cmd(cmds)
  end
end

---Opens the tree and displays the current path or cwd.
---@param callback function Callback to call after the items are loaded.
M.show = function(callback)
  local state = get_state()
  M.navigate(state.path, nil, callback)
end

---Expands or collapses the current node.
M.toggle_directory = function(node)
  local state = get_state()
  local tree = state.tree
  if not node then
    node = tree:get_node()
  end
  if node.type ~= "directory" then
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
    end
  end
end

return M
