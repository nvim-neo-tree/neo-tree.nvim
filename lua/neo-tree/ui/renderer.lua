local vim = vim
local NuiLine = require("nui.line")
local NuiTree = require("nui.tree")
local NuiSplit = require("nui.split")
local utils = require("neo-tree.utils")
local highlights = require("neo-tree.ui.highlights")

local M = {}

---Transforms a list of items into a collection of TreeNodes.
---@param sourceItems table The list of items to transform. The expected
--interface for these items depends on the component renderers configured for
--the given source, but they must contain at least an id field.
---@param state table The current state of the plugin.
---@param level integer Optional. The current level of the tree, defaults to 0.
---@return table A collection of TreeNodes.
M.createNodes = function(sourceItems, state, level)
  level = level or 0
  local nodes = {}
  local indent = ""
  local indentSize = state.indentSize or 2
  for _ = 1, level do
    for _ = 1, indentSize do
      indent = indent .. " "
    end
  end

  for _, item in ipairs(sourceItems) do
    local nodeData = {
      id = item.id,
      ext = item.ext,
      name = item.name,
      path = item.path,
      search_pattern = item.search_pattern,
      type = item.type,
      loaded = item.loaded,
      indent = indent
    }

    local nodeChildren = nil
    if item.children ~= nil then
      nodeChildren = M.createNodes(item.children, state, level + 1)
    end

    local node = NuiTree.Node(nodeData, nodeChildren)
    if item._is_expanded then
      node:expand()
    end
    table.insert(nodes, node)
  end
  return nodes
end

local prepare_node = function(item, state)
    local line = NuiLine()
    line:append(item.indent, highlights.NORMAL)

    local renderer = state.renderers[item.type]
    if not renderer then
      line:append(item.type .. ': ', "Comment")
      line:append(item.name, highlights.NORMAL)
    else
      for _,component in ipairs(renderer) do
        local componentData = state.functions[component[1]](component, item, state)
        line:append(componentData.text, componentData.highlight)
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

M.set_expanded_nodes = function(tree, expanded_nodes)
  for _, id in ipairs(expanded_nodes or {}) do
    local node = tree:get_node(id)
    if node ~= nil then
      node:expand()
    end
  end
end

local createTree = function(state)
  state.tree = NuiTree({
    winid = state.split.winid,
    get_node_id = function(node)
      return node.id
    end,
    prepare_node = function(data)
      return prepare_node(data, state)
    end,
  })
end

local createWindow = function(state)
    state.split = NuiSplit({
      relative = "editor",
      position = utils.getValue(state, "window.position", "left"),
      size = utils.getValue(state, "window.size", 40),
      win_options = {
        number = false,
        wrap = false,
      },
      buf_options = {
        bufhidden = "delete",
        buftype = "nowrite",
        modifiable = false,
        swapfile = false,
        filetype = "neo-tree",
      }
    })
    state.split:mount()
    local winid = state.split.winid
    state.bufid = vim.api.nvim_win_get_buf(winid)
    state.split:on({ "BufDelete" }, function()
      state.split:unmount()
      state.split = nil
    end, { once = true })

    local map_options = { noremap = true, nowait = true }
    local mappings = utils.getValue(state, "window.mappings", {})
    for cmd, func in pairs(mappings) do
      if type(func) == "string" then
        func = state.commands[func]
      end
      state.split:map('n', cmd, function()
        func(state)
      end, map_options)
    end
    return state.split
end

---Determines of the window exists and is valid.
---@param state table The current state of the plugin.
---@return boolean True if the window exists and is valid, false otherwise.
M.window_exists = function(state)
  local window_exists
  if state.split == nil then
    print("state.split is nil")
    window_exists = false
  else
    local isvalid = vim.api.nvim_win_is_valid(state.split.winid)
    window_exists = isvalid and (vim.api.nvim_win_get_number(state.split.winid) > 0)
    if not window_exists then
      print("Tree window is invalid")
      if vim.api.nvim_buf_is_valid(state.bufid) then
        vim.api.nvim_buf_delete(state.bufid, {force = true})
      end
    end
  end
  return window_exists
end

---Draws the given nodes on the screen.
--@param nodes table The nodes to draw.
--@param state table The current state of the source.
M.draw = function(nodes, state, parentId)
  -- If we are going to redraw, preserve the current set of expanded nodes.
  local expanded_nodes = {}
  if parentId == nil and state.tree ~= nil then
    expanded_nodes = M.get_expanded_nodes(state.tree)
  end
  for _, id in ipairs(state.default_expanded_nodes) do
    table.insert(expanded_nodes, id)
  end

  -- Create the tree if it doesn't exist.
  if not M.window_exists(state) then
    createWindow(state)
    createTree(state)
  end

  -- draw the given nodes
  state.tree:set_nodes(nodes, parentId)
  if parentId ~= nil then
    -- this is a dynamic fetch of children that were not previously loaded
    local node = state.tree:get_node(parentId)
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
M.showNodes = function(sourceItems, state, parentId)
  local level = 0
  if parentId ~= nil then
    local parent = state.tree:get_node(parentId)
    level = parent:get_depth()
  end
  local nodes = M.createNodes(sourceItems, state, level)
  M.draw(nodes, state, parentId)
end

return M
