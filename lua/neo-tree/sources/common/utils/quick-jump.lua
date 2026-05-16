local utils = require("neo-tree.utils")
local M = {}

---@param first_char string
---@param count integer
---@param jump_labels string
---@return string hotkey
local compute_hotkey = function(first_char, count, jump_labels)
  local labels = first_char .. string.gsub(jump_labels, first_char, "")
  local labels_len = #labels

  -- compute length
  local length = 1
  local prev = 0
  local sum = labels_len ^ length
  while sum < count do
    length = length + 1
    prev = sum
    sum = sum + labels_len ^ length
  end

  local rest = count - prev - 1

  -- generate hotkey
  local hotkey = first_char
  local q
  while length > 0 do
    q = math.floor(rest / (labels_len ^ (length - 1)) + 1)
    hotkey = hotkey .. string.sub(labels, q, q)
    rest = rest % (labels_len ^ (length - 1))
    length = length - 1
  end

  return hotkey
end

---@return table<string, integer> head
local generate_cnttbl = function()
  local head = {}
  for c = string.byte("a"), string.byte("z") do
    head[string.char(c)] = 1
  end
  return head
end

---@param name string
---@return string c
local fst_ch_in_filename = function(name)
  if type(name) ~= "string" then
    return "j"
  end

  local c = string.match(name, "[A-Za-z]")
  if c then
    return string.lower(c)
  end

  return "j"
end

-- Return key - node pairs whose key starts by ch.
---@param node2key table<neotree.FileNode, string>
---@param ch string
---@param depth integer
---@return table<neotree.FileNode, string> candidate
M.get_candidate = function(node2key, ch, depth)
  local candidate = {}
  for node, key in pairs(node2key) do
    if #key >= depth then
      local fst = string.sub(key, depth, depth)
      if fst == ch then
        candidate[node] = key
      end
    end
  end
  return candidate
end

-- Generate hotkeys map.
-- Hotkeys will take the first letter of the node name to be the leader,
-- and assign the rest according to the priority of the jump labels in the config.
-- The length is computed dynamiclly.
-- It will be like {leader}{label_1}{label_2}{label_3}......
---@param nodes_name table<neotree.FileNode, { b: boolean, name: string }>
---@param jump_labels string
---@return table<neotree.FileNode, string> node2key
M.assign_hotkeys = function(nodes_name, jump_labels)
  local node2key = {}

  local cnttbl = generate_cnttbl()

  -- Assign opened buffers more convenient keys.
  local opened_buffers = require("neo-tree.utils").get_opened_buffers()
  for node, value in pairs(nodes_name) do
    local name = value.name
    if opened_buffers[name] ~= nil then
      local fst = fst_ch_in_filename(name)
      local cnt = cnttbl[fst]
      cnttbl[fst] = cnt + 1
      local hotkey = compute_hotkey(fst, cnt, jump_labels)
      node2key[node] = hotkey
      nodes_name[node].b = false
    end
  end

  -- Handle the rest.
  for node, value in pairs(nodes_name) do
    if value.b then
      local name = nodes_name[node].name
      local fst = fst_ch_in_filename(name)
      local cnt = cnttbl[fst]
      cnttbl[fst] = cnt + 1
      local hotkey = compute_hotkey(fst, cnt, jump_labels)
      node2key[node] = hotkey
    end
  end

  return node2key
end

-- Expand / collapse a directory node.
local toggle_directory = function(node)
  if node.type == "directory" then
    if node:is_expanded() then
      node:collapse()
    else
      node:expand()
    end
  end
end

-- Open / toggle node.
M.open_or_toggle_node = function(state, node)
  local fs = require("neo-tree.sources.filesystem")

  if state.name == "filesystem" then
    if node.type == "file" then
      utils.open_file(state, node.path, "e", node.extra and node.extra.bufnr)
    elseif node.type == "directory" then
      fs.toggle_directory(state, node, nil)
    end
  end

  if state.name == "document_symbols" then
    local sym = require("neo-tree.sources.document_symbols.commands")
    sym.jump_to_symbol(state, node)
  end

  if state.name == "git_status" then
    if node.type == "file" then
      utils.open_file(state, node.path, "e", node.extra and node.extra.bufnr)
    elseif node.type == "directory" then
      toggle_directory(node)
    end
  end

  if state.name == "buffers" then
    if node.type == "file" then
      utils.open_file(state, node.path, "e", node.extra and node.extra.bufnr)
    elseif node.type == "directory" then
      toggle_directory(node)
    elseif node.type == "terminal" then
      M.open_file(state, node:get_id(), "e", node.extra and node.extra.bufnr)
    end
  end
end

return M
