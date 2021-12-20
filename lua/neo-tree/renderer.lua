local vim = vim
local NuiLine = require("nui.line")
local NuiTree = require("nui.tree")
local NuiSplit = require("nui.split")
local utils = require("neo-tree.utils")

local M = {}
local highlights = {
  NORMAL = "NvimTreeNormal"
}

---Transforms a list of items into a collection of TreeNodes.
---@param sourceItems table The list of items to transform. The expected
--interface for these items depends on the component renderers configured for
--the given source, but they must contain at least an id field.
---@param state table The current state of the plugin.
---@param level integer Optional. The current level of the tree, defaults to 0.
---@param nodes table Optional. The current collection of nodes, defaults to {}.
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
    local existing = state.tree and state.tree:get_node(item.id)
    if existing then
      state.expanded_nodes = state.expanded_nodes or {}
      if existing:is_expanded() then
        state.expanded_nodes[item.id] = true
      else
        if state.expanded_nodes[item.id] then
          state.expanded_nodes[item.id] = nil
        end
      end
    end

    local nodeData = {
      id = item.id,
      ext = item.ext,
      _is_expanded = existing and existing:is_expanded(),
      name = item.name,
      path = item.path,
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
    for _,component in ipairs(renderer) do
      local componentData = state.functions[component[1]](component, item, state)
      line:append(componentData.text, componentData.highlight)
    end
    return line
end

local restoreExpandedNodes = function(state)
  for id, is_expanded in pairs(state.expanded_nodes or {}) do
    if is_expanded then
      local node = state.tree:get_node(id)
      if node ~= nil then
        node:expand()
      end
    end
  end
end

---Draws the given nodes on the screen.
--@param nodes table The nodes to draw.
--@param state table The current state of the source.
M.draw = function(nodes, state, parentId)
  if state.split == nil then
    state.split = NuiSplit({
      relative = "editor",
      position = utils.getValue(state, "window.position", "left"),
      size = utils.getValue(state, "window.size", 40),
    })
    state.split:mount()
    state.split:on({ "BufDelete" }, function()
      state.split:unmount()
      state.split = nil
    end, { once = true })

    state.tree = NuiTree({
      winid = state.split.winid,
      nodes = nodes,
      get_node_id = function(node)
        return node.id
      end,
      prepare_node = function(data)
        return prepare_node(data, state)
      end,
    })
    restoreExpandedNodes(state)

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
  else
    state.tree:set_nodes(nodes, parentId)
    if parentId ~= nil then
      local node = state.tree:get_node(parentId)
      node.loaded = true
      node:expand()
    else
      restoreExpandedNodes(state)
    end
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
