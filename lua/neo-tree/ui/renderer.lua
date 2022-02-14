local vim = vim
local NuiLine = require("nui.line")
local NuiTree = require("nui.tree")
local NuiSplit = require("nui.split")
local NuiPopup = require("nui.popup")
local utils = require("neo-tree.utils")
local highlights = require("neo-tree.ui.highlights")
local popups = require("neo-tree.ui.popups")
local events = require("neo-tree.events")
local keymap = require("nui.utils.keymap")
local autocmd = require("nui.utils.autocmd")
local log = require("neo-tree.log")

local M = {}
local floating_windows = {}
local draw, create_window, create_tree

M.close = function(state)
  local window_existed = false
  if state and state.winid then
    if M.window_exists(state) then
      local bufnr = vim.api.nvim_win_get_buf(state.winid)
      -- if bufnr is different then we expect,  then it was taken over by
      -- another buffer, so we can't delete it now
      if bufnr == state.bufnr then
        window_existed = true
        if state.current_position == "split" then
          -- we are going to hide the buffer instead of closing the window
          M.position.save(state)
          local new_buf = vim.fn.bufnr("#")
          if new_buf < 1 then
            new_buf = vim.api.nvim_create_buf(true, false)
          end
          vim.api.nvim_win_set_buf(state.winid, new_buf)
        else
          vim.api.nvim_win_close(state.winid, true)
        end
      end
    end
    state.winid = nil
  end
  local bufnr = utils.get_value(state, "bufnr", 0, true)
  if bufnr > 0 then
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    state.bufnr = nil
  end
  return window_existed
end

M.close_floating_window = function(source_name)
  local found_windows = {}
  for _, win in ipairs(floating_windows) do
    if win.source_name == source_name then
      table.insert(found_windows, win)
    end
  end

  local valid_window_was_closed = false
  for _, win in ipairs(found_windows) do
    if not valid_window_was_closed then
      valid_window_was_closed = M.is_window_valid(win.winid)
    end
    -- regardless of whether the window is valid or not, nui will cleanup
    win:unmount()
  end
  return valid_window_was_closed
end

M.close_all_floating_windows = function()
  while #floating_windows > 0 do
    local win = table.remove(floating_windows)
    win:unmount()
  end
end

local create_nodes
---Transforms a list of items into a collection of TreeNodes.
---@param source_items table The list of items to transform. The expected
--interface for these items depends on the component renderers configured for
--the given source, but they must contain at least an id field.
---@param state table The current state of the plugin.
---@param level integer Optional. The current level of the tree, defaults to 0.
---@return table A collection of TreeNodes.
create_nodes = function(source_items, state, level)
  level = level or 0
  local nodes = {}

  for i, item in ipairs(source_items) do
    local is_last_child = i == #source_items

    local nodeData = {
      id = item.id,
      name = item.name,
      type = item.type,
      loaded = item.loaded,
      extra = item.extra,
      is_link = item.is_link,
      link_to = item.link_to,
      -- TODO: The below properties are not universal and should not be here.
      -- Maybe they should be moved to a a "data" or "extra" field?
      path = item.path,
      ext = item.ext,
      search_pattern = item.search_pattern,
      level = level,
      is_last_child = is_last_child,
    }

    local node_children = nil
    if item.children ~= nil then
      node_children = create_nodes(item.children, state, level + 1)
    end

    local node = NuiTree.Node(nodeData, node_children)
    if item._is_expanded then
      node:expand()
    end
    table.insert(nodes, node)
  end
  return nodes
end

local one_line = function(text)
  if type(text) == "string" then
    return text:gsub("\n", " ")
  else
    return text
  end
end

local prepare_node = function(item, state)
  local line = NuiLine()

  local renderer = state.renderers[item.type]
  if not renderer then
    line:append(item.type .. ": ", "Comment")
    line:append(item.name)
  else
    for _, component in ipairs(renderer) do
      local component_func = state.components[component[1]]
      if component_func then
        local success, component_data = pcall(component_func, component, item, state)
        if success then
          if component_data[1] then
            -- a list of text objects
            for _, data in ipairs(component_data) do
              line:append(one_line(data.text), data.highlight)
            end
          else
            line:append(one_line(component_data.text), component_data.highlight)
          end
        else
          local name = component[1] or "[missing_name]"
          local msg = string.format("Error rendering component %s: %s", name, component_data)
          line:append(msg, highlights.NORMAL)
        end
      else
        local name = component[1] or "[missing_name]"
        log.error("Neo-tree: Component " .. name .. " not found.")
      end
    end
  end
  return line
end

---Sets the cursor at the specified node.
---@param state table The current state of the source.
---@param id string The id of the node to set the cursor at.
---@return boolean boolean True if the node was found and focused, false
---otherwise.
M.focus_node = function(state, id, do_not_focus_window, relative_movement, bottom_scroll_padding)
  if not id and not relative_movement then
    log.debug("focus_node called with no id and no relative movement")
    return nil
  end
  relative_movement = relative_movement or 0
  bottom_scroll_padding = bottom_scroll_padding or 0

  local tree = state.tree
  if not tree then
    log.debug("focus_node called with no tree")
    return false
  end
  local node = tree:get_node(id)
  if not node then
    log.debug("focus_node cannot find node with id ", id)
    return false
  end
  id = node:get_id() -- in case nil was passed in for id, meaning current node

  local bufnr = utils.get_value(state, "bufnr", 0, true)
  if bufnr == 0 then
    log.debug("focus_node: state has no bufnr ", state.bufnr, " / ", state.winid)
    return false
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("focus_node: bufnr is not valid")
    return false
  end
  local lines = vim.api.nvim_buf_line_count(state.bufnr)
  local linenr = 0
  while linenr < lines do
    linenr = linenr + 1
    node = tree:get_node(linenr)
    if node then
      if node:get_id() == id then
        if relative_movement ~= 0 then
          local success, relative_node = pcall(tree.get_node, tree, linenr)
          -- this may fail if the node is at the first or last line
          if success and relative_node then
            node = relative_node
            linenr = linenr + relative_movement
          end
        end
        local col = 0
        if node.indent then
          col = string.len(node.indent)
        end
        local focus_window = not do_not_focus_window
        if M.window_exists(state) then
          if focus_window then
            vim.api.nvim_set_current_win(state.winid)
          end
          local success, err = pcall(vim.api.nvim_win_set_cursor, state.winid, { linenr, col })
          if success then
            local execute_win_command = function(cmd)
              if vim.api.nvim_get_current_win() == state.winid then
                vim.cmd(cmd)
              else
                vim.cmd("call win_execute(" .. state.winid .. [[, "]] .. cmd .. [[")]])
              end
            end

            -- make sure we are not scrolled down if it can all fit on the screen
            local win_height = vim.api.nvim_win_get_height(state.winid)
            local expected_bottom_line = math.min(lines, linenr + 5) + bottom_scroll_padding
            if expected_bottom_line > win_height then
              execute_win_command("normal! zb")
              local top = vim.fn.line("w0", state.winid)
              local bottom = vim.fn.line("w$", state.winid)
              local offset_top = top + (expected_bottom_line - bottom)
              execute_win_command("normal! " .. offset_top .. "zt")
              pcall(vim.api.nvim_win_set_cursor, state.winid, { linenr, col })
            elseif win_height > linenr then
              execute_win_command("normal! zb")
            elseif linenr < (win_height / 2) then
              execute_win_command("normal! zz")
            end
          else
            log.debug("Failed to set cursor: " .. err)
          end
          return success
        else
          log.debug("focus_node: window does not exist")
          return false
        end
      end
    else
      --must be out of nodes
      log.debug("focus_node: node not found")
      return false
    end
  end
  return false
end

M.get_all_visible_nodes = function(tree)
  local nodes = {}

  local function process(node)
    table.insert(nodes, node)
    if node:is_expanded() then
      if node:has_children() then
        for _, child in ipairs(tree:get_nodes(node:get_id())) do
          process(child)
        end
      end
    end
  end

  for _, node in ipairs(tree:get_nodes()) do
    process(node)
  end
  return nodes
end

M.get_expanded_nodes = function(tree, root_node_id)
  local node_ids = {}

  local function process(node)
    if node:is_expanded() then
      local id = node:get_id()
      table.insert(node_ids, id)

      if node:has_children() then
        for _, child in ipairs(tree:get_nodes(id)) do
          process(child)
        end
      end
    end
  end

  if root_node_id then
    local root_node = tree:get_node(root_node_id)
    if root_node then
      process(root_node)
    end
  else
    for _, node in ipairs(tree:get_nodes()) do
      process(node)
    end
  end
  return node_ids
end

M.collapse_all_nodes = function(tree)
  local expanded = M.get_expanded_nodes(tree)
  for _, id in ipairs(expanded) do
    local node = tree:get_node(id)
    node:collapse(id)
  end
  -- but make sure the root is expanded
  local root = tree:get_nodes()[1]
  root:expand()
end

---Functions to save and restore the focused node.
M.position = {
  save = function(state)
    if state.tree and M.window_exists(state) then
      local node = state.tree:get_node()
      if node then
        state.position.node_id = node:get_id()
      end
    end
    -- Only need to restore the cursor state once per save, comes
    -- into play when some actions fire multiple times per "iteration"
    -- within the scope of where we need to perform the restore operation
    state.position.is.restorable = true
  end,
  set = function(state, node_id)
    if not type(node_id) == "string" and node_id > "" then
      return
    end
    state.position.node_id = node_id
    state.position.is.restorable = true
  end,
  restore = function(state)
    if not state.position.node_id then
      log.debug("No node_id to restore to")
      return
    end
    if state.position.is.restorable then
      log.debug("Restoring position to node_id: " .. state.position.node_id)
      M.focus_node(state, state.position.node_id, true)
    else
      log.debug("Position is not restorable")
    end
    state.position.is.restorable = false
  end,
  is = { restorable = true },
}

---Visits all nodes in the tree and returns a list of all nodes that match the
---given predicate.
---@param tree table The NuiTree to search.
---@param selector_func function The predicate function, should return true for
---nodes that should be included in the result.
---@return table table A list of nodes that match the predicate.
M.select_nodes = function(tree, selector_func)
  if type(selector_func) ~= "function" then
    error("selector_func must be a function")
  end
  local found_nodes = {}
  local visit
  visit = function(node)
    if selector_func(node) then
      table.insert(found_nodes, node)
    end
    if node:has_children() then
      for _, child in ipairs(tree:get_nodes(node:get_id())) do
        visit(child)
      end
    end
  end
  for _, node in ipairs(tree:get_nodes()) do
    visit(node)
  end
  return found_nodes
end

M.set_expanded_nodes = function(tree, expanded_nodes)
  M.collapse_all_nodes(tree)
  log.debug("Setting expanded nodes")
  for _, id in ipairs(expanded_nodes or {}) do
    local node = tree:get_node(id)
    if node ~= nil then
      node:expand()
    end
  end
end

create_tree = function(state)
  state.tree = NuiTree({
    winid = state.winid,
    get_node_id = function(node)
      return node.id
    end,
    prepare_node = function(data)
      return prepare_node(data, state)
    end,
  })
end

create_window = function(state)
  local default_position = utils.resolve_config_option(state, "window.position", "left")
  state.current_position = state.current_position or default_position

  local bufname = string.format("neo-tree %s [%s]", state.name, state.id)
  local win_options = {
    size = utils.resolve_config_option(state, "window.width", "40"),
    position = state.current_position,
    relative = "editor",
    buf_options = {
      buftype = "nowrite",
      modifiable = false,
      swapfile = false,
      filetype = "neo-tree",
    },
  }

  local win
  if state.current_position == "float" then
    state.force_float = nil
    -- First get the default options for floating windows.
    local sourceTitle = state.name:gsub("^%l", string.upper)
    win_options = popups.popup_options("Neo-tree " .. sourceTitle, 40, win_options)
    win_options.win_options = nil
    win_options.zindex = 40
    local size = { width = 60, height = "80%" }

    -- Then override with source specific options.
    local b = win_options.border
    win_options.size = utils.resolve_config_option(state, "window.popup.size", size)
    win_options.position = utils.resolve_config_option(state, "window.popup.position", "50%")
    win_options.border = utils.resolve_config_option(state, "window.popup.border", b)

    win = NuiPopup(win_options)
    win:mount()
    win.source_name = state.name
    table.insert(floating_windows, win)

    if require("neo-tree").config.close_floats_on_escape_key then
      win:map("n", "<esc>", function(_)
        win:unmount()
      end, { noremap = true })
    end

    win:on({ "BufHidden" }, function()
      vim.schedule(function()
        win:unmount()
      end)
    end, { once = true })
    state.winid = win.winid
    state.bufnr = win.bufnr
    log.debug("Created floating window with winid: ", win.winid, " and bufnr: ", win.bufnr)
    vim.api.nvim_buf_set_name(state.bufnr, bufname)

    -- why is this necessary?
    vim.api.nvim_set_current_win(win.winid)
  elseif state.current_position == "split" then
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.fn.bufnr(bufname)
    if bufnr < 1 then
      bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, bufname)
    end
    state.winid = winid
    state.bufnr = bufnr
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "neo-tree")
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_win_set_buf(winid, bufnr)
  else
    win = NuiSplit(win_options)
    win:mount()
    state.winid = win.winid
    state.bufnr = win.bufnr
    vim.api.nvim_buf_set_name(state.bufnr, bufname)
  end

  if type(state.bufnr) == "number" then
    vim.api.nvim_buf_set_var(state.bufnr, "neo_tree_source", state.name)
    vim.api.nvim_buf_set_var(state.bufnr, "neo_tree_tabnr", state.tabnr)
    vim.api.nvim_buf_set_var(state.bufnr, "neo_tree_position", state.current_position)
    vim.api.nvim_buf_set_var(state.bufnr, "neo_tree_winid", state.winid)
  end

  if win == nil then
    autocmd.buf.define(state.bufnr, "WinLeave", function()
      M.position.save(state)
    end)
  else
    -- Used to track the position of the cursor within the tree as it gains and loses focus
    --
    -- Note `WinEnter` is often too early to restore the cursor position so we do not set
    -- that up here, and instead trigger those events manually after drawing the tree (not
    -- to mention that it would be too late to register `WinEnter` here for the first
    -- iteration of that event on the tree window)
    win:on({ "WinLeave" }, function()
      M.position.save(state)
    end)

    win:on({ "BufDelete" }, function()
      win:unmount()
    end, { once = true })
  end

  local skip_this_mapping = {
    ["none"] = true,
    ["nop"] = true,
    ["noop"] = true,
    [""] = true,
    [{}] = true,
  }
  local map_options = { noremap = true, nowait = true }
  local mappings = utils.get_value(state, "window.mappings", {}, true)
  for cmd, func in pairs(mappings) do
    if func then
      if skip_this_mapping[func] then
        log.trace("Skipping mapping for %s", cmd)
      else
        if type(func) == "string" then
          func = state.commands[func]
        end
        if type(func) == "function" then
          keymap.set(state.bufnr, "n", cmd, function()
            func(state)
          end, map_options)
        else
          log.warn("Invalid mapping for ", cmd, ": ", func)
        end
      end
    end
  end
  return win
end

---Determines is the givin winid is valid and the window still exists.
---@param winid any
---@return boolean
M.is_window_valid = function(winid)
  if winid == nil then
    return false
  end
  if type(winid) == "number" and winid > 0 then
    return vim.api.nvim_win_is_valid(winid)
  else
    return false
  end
end

---Determines if the window exists and is valid.
---@param state table The current state of the plugin.
---@return boolean True if the window exists and is valid, false otherwise.
M.window_exists = function(state)
  local window_exists
  local winid = utils.get_value(state, "winid", 0, true)
  local bufnr = utils.get_value(state, "bufnr", 0, true)
  local default_position = utils.get_value(state, "window.position", "left", true)
  local position = state.current_position or default_position

  if winid == 0 then
    window_exists = false
  elseif position == "split" then
    window_exists = vim.api.nvim_win_is_valid(winid)
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_win_get_buf(winid) == bufnr
  else
    local isvalid = M.is_window_valid(winid)
    window_exists = isvalid and (vim.api.nvim_win_get_number(winid) > 0)
    if not window_exists then
      state.winid = nil
      if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
        state.bufnr = nil
        local success, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        if not success and err:match("E523") then
          vim.schedule_wrap(function()
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end)()
        end
      end
    end
  end
  return window_exists
end

---Draws the given nodes on the screen.
--@param nodes table The nodes to draw.
--@param state table The current state of the source.
draw = function(nodes, state, parent_id)
  -- If we are going to redraw, preserve the current set of expanded nodes.
  local expanded_nodes = {}
  if parent_id == nil and state.tree ~= nil then
    if state.force_open_folders then
      log.trace("Force open folders")
      state.force_open_folders = nil
    else
      log.trace("Preserving expanded nodes")
      expanded_nodes = M.get_expanded_nodes(state.tree)
    end
  end
  for _, id in ipairs(state.default_expanded_nodes) do
    table.insert(expanded_nodes, id)
  end

  -- Create the tree if it doesn't exist.
  if not parent_id and not M.window_exists(state) then
    create_window(state)
    create_tree(state)
  end

  -- draw the given nodes
  local success, msg = pcall(state.tree.set_nodes, state.tree, nodes, parent_id)
  if not success then
    log.error("Error setting nodes: ", msg)
    log.error(vim.inspect(state.tree:get_nodes()))
  end
  if parent_id ~= nil then
    -- this is a dynamic fetch of children that were not previously loaded
    local node = state.tree:get_node(parent_id)
    node.loaded = true
    node:expand()
  else
    M.set_expanded_nodes(state.tree, expanded_nodes)
  end
  state.tree:render()

  -- Restore the cursor position/focused node in the tree based on the state
  -- when it was last closed
  M.position.restore(state)
end

---Shows the given items as a tree.
--@param sourceItems table The list of items to transform.
--@param state table The current state of the plugin.
--@param parentId string Optional. The id of the parent node to display these nodes
--at; defaults to nil.
M.show_nodes = function(sourceItems, state, parentId, callback)
  local id = string.format("show_nodes %s:%s [%s]", state.name, state.force_float, state.tabnr)
  utils.debounce(id, function()
    events.fire_event(events.BEFORE_RENDER, state)
    local level = 0
    if parentId ~= nil then
      local success, parent = pcall(state.tree.get_node, state.tree, parentId)
      if success then
        level = parent:get_depth()
      end
    end
    local nodes = create_nodes(sourceItems, state, level)
    draw(nodes, state, parentId)

    vim.schedule(function()
      events.fire_event(events.AFTER_RENDER, state)
    end)
    if type(callback) == "function" then
      vim.schedule(callback)
    end
  end, 100)
end

return M
