local log = require("neo-tree.log")

local M = {}

--- Recursively expand all loaded nodes under the given node
--- returns table with all discovered nodes that need to be loaded 
---@param node table a node to expand
---@param state table current state of the source
---@return table discovered nodes that need to be loaded
local function expand_loaded(node, state, node_expander)
    local function rec(current_node, to_load)
      if node_expander.should_prefetch(current_node) then
        log.trace("Node " .. current_node:get_id() .. "not loaded, saving for later")
        table.insert(to_load, current_node)
      else
        if not current_node:is_expanded() then
          current_node:expand()
          state.explicitly_opened_directories[current_node:get_id()] = true
        end
        local children = state.tree:get_nodes(current_node:get_id())
        log.debug("Expanding childrens of " .. current_node:get_id())
        for _, child in ipairs(children) do
          if child.type == "directory" then
             rec(child, to_load)
          else
            log.trace("Child: " .. child.name .. " is not a directory, skipping")
          end
        end
      end
    end

    local to_load = {}
    rec(node, to_load)
    return to_load
end

--- Recursively expands all nodes under the given node
--- loading nodes if necessary.
--- async method
---@param node table a node to expand
---@param state table current state of the source
local function expand_and_load(node, state, node_expander)
    local function rec(to_load, progress)
      local to_load_current = expand_loaded(node, state, node_expander)
      for _,v in ipairs(to_load_current) do
        table.insert(to_load, v)
      end
      if progress <= #to_load then
        M.expand_directory_recursively(state, to_load[progress], node_expander)
        rec(to_load, progress + 1)
      end
    end
    rec({}, 1)
end

--- Expands given node recursively loading all descendant nodes if needed
--- async method
---@param state table current state of the source
---@param node table a node to expand
M.expand_directory_recursively = function(state, node, node_expander)
  log.debug("Expanding directory " .. node:get_id())
  if node.type ~= "directory" then
    return
  end
  state.explicitly_opened_directories = state.explicitly_opened_directories or {}
  if node_expander.should_prefetch(node) then
    local id = node:get_id()
    state.explicitly_opened_directories[id] = true
    node_expander.prefetch(state, node)
    expand_loaded(node, state, node_expander)
  else
    expand_and_load(node, state, node_expander)
  end
end

M.default_expander = {
  prefetch = function (state, node)
    log.debug("Default expander prefetch does nothing")
  end,
  should_prefetch = function (node)
    return false
  end
}

return M
