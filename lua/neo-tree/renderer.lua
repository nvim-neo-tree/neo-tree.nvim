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
    local line = NuiLine()
    line:append(indent, highlights.NORMAL)

    local renderer = state.renderers[item.type]
    for _,component in ipairs(renderer) do
      local componentData = state.functions[component[1]](component, item, state)
      line:append(componentData.text, componentData.highlight)
    end

    local nodeData = {
      id = item.id,
      line = line,
    }

    local nodeChildren = nil
    if item.children ~= nil then
      nodeChildren = M.createNodes(item.children, state, level + 1)
    end

    local node = NuiTree.Node(nodeData, nodeChildren)
    table.insert(nodes, node)
  end
  return nodes
end

---Draws the given nodes to the given window.
--@param nodes table The nodes to draw.
--@param state table The current state of the plugin.
M.draw = function(nodes, state)
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
      prepare_node = function(data)
        return data.line
      end,
    })

    local map_options = { noremap = true, nowait = true }
    local mappings = utils.getValue(state, "window.mappings", {})
    for cmd, func in pairs(mappings) do
      state.split:map('n', cmd, function()
        print("neo-tree mapping: " .. cmd)
        func(state)
      end, map_options)
    end
  else
    state.tree.nodes = nodes
  end

  state.tree:render()
end

---Shows the given items as a tree. This is a convienence methid that sends the
--output of createNodes() to draw().
--@param sourceItems table The list of items to transform.
--@param state table The current state of the plugin.
M.showNodes = function(sourceItems, state)
  local nodes = M.createNodes(sourceItems, state)
  print(vim.inspect(nodes))
  M.draw(nodes, state)
end

return M
