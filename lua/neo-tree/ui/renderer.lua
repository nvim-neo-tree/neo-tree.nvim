local vim = vim
local NuiLine = require("nui.line")
local NuiTree = require("nui.tree")
local NuiSplit = require("nui.split")
local utils = require("neo-tree.utils")
local highlights = require("neo-tree.ui.highlights")

local M = {}

M.close = function(state)
  if state and state.winid then
    if M.window_exists(state) then
      local winid = utils.get_value(state, "split.winid", 0, true)
      vim.api.nvim_win_close(winid, true)
    end
    state.split = nil
    state.NuiWindow = nil
    state.winid = nil
  end
  local bufnr = utils.get_value(state, "bufnr", 0, true)
  if bufnr > 0 then
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, {force = true})
    end
    state.bufnr = nil
  end
end

---Transforms a list of items into a collection of TreeNodes.
---@param source_items table The list of items to transform. The expected
--interface for these items depends on the component renderers configured for
--the given source, but they must contain at least an id field.
---@param state table The current state of the plugin.
---@param level integer Optional. The current level of the tree, defaults to 0.
---@return table A collection of TreeNodes.
M.create_nodes = function(source_items, state, level)
  level = level or 0
  local nodes = {}
  local indent = ""
  local indent_size = state.indent_size or 2
  for _ = 1, level do
    for _ = 1, indent_size do
      indent = indent .. " "
    end
  end

  for _, item in ipairs(source_items) do
    local nodeData = {
      id = item.id,
      name = item.name,
      type = item.type,
      loaded = item.loaded,
      indent = indent,
      extra = item.extra,
      -- TODO: The below properties are not universal and should not be here.
      -- Maybe they should be moved to a a "data" or "extra" field?
      path = item.path,
      ext = item.ext,
      search_pattern = item.search_pattern,
    }

    local node_children = nil
    if item.children ~= nil then
      node_children = M.create_nodes(item.children, state, level + 1)
    end

    local node = NuiTree.Node(nodeData, node_children)
    if item._is_expanded then
      node:expand()
    end
    table.insert(nodes, node)
  end
  return nodes
end

local prepare_node = function(item, state)
    local line = NuiLine()
    line:append(item.indent)

    local renderer = state.renderers[item.type]
    if not renderer then
      line:append(item.type .. ': ', "Comment")
      line:append(item.name)
    else
      for _,component in ipairs(renderer) do
        local component_func = state.components[component[1]]
        if component_func then
          local success, component_data = pcall(component_func, component, item, state)
          if success then
            if component_data[1] then
              -- a list of text objects
              for _,data in ipairs(component_data) do
                line:append(data.text, data.highlight)
              end
            else
              line:append(component_data.text, component_data.highlight)
            end
          else
            local name = component[1] or "[missing_name]"
            local msg = string.format(
              "Error rendering component %s: %s", name, component_data)
            line:append(msg, highlights.NORMAL)
          end
        else
          print("Neo-tree: Component " .. component[1] .. " not found.")
        end
      end
    end
    return line
end

M.get_expanded_nodes = function(tree)
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

  for _, node in ipairs(tree:get_nodes()) do
    process(node)
  end
  return node_ids
end

M.collapse_all_nodes = function(tree)
  local function collapse_all(parent_node)
    if parent_node:has_children() then
      for _, child in ipairs(tree:get_nodes(parent_node:get_id())) do
        child:collapse()
      end
      parent_node:collapse()
    end
  end

  for _, node in ipairs(tree:get_nodes()) do
    collapse_all(node)
  end
end

M.set_expanded_nodes = function(tree, expanded_nodes)
  M.collapse_all_nodes(tree)
  for _, id in ipairs(expanded_nodes or {}) do
    local node = tree:get_node(id)
    if node ~= nil then
      node:expand()
    end
  end
end

local create_tree = function(state)
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

local create_window = function(state)
  local winhl = string.format("Normal:%s,NormalNC:%s,CursorLine:%s",
    highlights.NORMAL, highlights.NORMALNC, highlights.CURSOR_LINE)
  local position = utils.get_value(state, "window.position", "left", true)

  local split = NuiSplit({
    relative = "editor",
    position = position,
    size = utils.get_value(state, "window.size", 40),
    win_options = {
      number = false,
      wrap = false,
      winhighlight = winhl,
    },
    buf_options = {
      bufhidden = "delete",
      buftype = "nowrite",
      modifiable = false,
      swapfile = false,
      filetype = "neo-tree",
    }
  })
  split:mount()

  state.split = split
  state.NuiWindow = split
  state.winid = split.winid
  state.bufnr = split.bufnr

  if type(state.bufnr) == "number" then
    local bufname = string.format("neo-tree %s [%s]", state.name, state.tabnr)
    vim.api.nvim_buf_set_name(state.bufnr, bufname)
  end

  split:on({ "BufDelete" }, function()
    split:unmount()
    split = nil
  end, { once = true })

  local map_options = { noremap = true, nowait = true }
  local mappings = utils.get_value(state, "window.mappings", {}, true)
  for cmd, func in pairs(mappings) do
    if func then
      if type(func) == "string" then
        func = state.commands[func]
      end
      split:map('n', cmd, function()
        func(state)
      end, map_options)
    end
  end
  return split
end

---Determines if the window exists and is valid.
---@param state table The current state of the plugin.
---@return boolean True if the window exists and is valid, false otherwise.
M.window_exists = function(state)
  local window_exists
  if state.winid == nil then
    window_exists = false
  else
    local winid = utils.get_value(state, "split.winid", 0, true)
    local isvalid = winid > 0 and vim.api.nvim_win_is_valid(winid)
    window_exists = isvalid and (vim.api.nvim_win_get_number(winid) > 0)
    if not window_exists then
      local bufnr = utils.get_value(state, "bufnr", 0, true)
      if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, {force = true})
      end
    end
  end
  return window_exists
end

---Draws the given nodes on the screen.
--@param nodes table The nodes to draw.
--@param state table The current state of the source.
M.draw = function(nodes, state, parent_id)
  -- If we are going to redraw, preserve the current set of expanded nodes.
  local expanded_nodes = {}
  if parent_id == nil and state.tree ~= nil then
    expanded_nodes = M.get_expanded_nodes(state.tree)
  end
  for _, id in ipairs(state.default_expanded_nodes) do
    table.insert(expanded_nodes, id)
  end

  -- Create the tree if it doesn't exist.
  if not M.window_exists(state) then
    create_window(state)
    create_tree(state)
  end

  -- draw the given nodes
  state.tree:set_nodes(nodes, parent_id)
  if parent_id ~= nil then
    -- this is a dynamic fetch of children that were not previously loaded
    local node = state.tree:get_node(parent_id)
    node.loaded = true
    node:expand()
  else
    M.set_expanded_nodes(state.tree, expanded_nodes)
  end
  state.tree:render()
end

---Shows the given items as a tree. This is a convienence methid that sends the
--output of createNodes() to draw().
--@param sourceItems table The list of items to transform.
--@param state table The current state of the plugin.
--@param parentId string Optional. The id of the parent node to display these nodes
--at; defaults to nil.
M.show_nodes = function(sourceItems, state, parentId)
  local level = 0
  if parentId ~= nil then
    local parent = state.tree:get_node(parentId)
    level = parent:get_depth()
  end
  local nodes = M.create_nodes(sourceItems, state, level)
  M.draw(nodes, state, parentId)
end

return M
