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

---@param name string
---@return string c
local first_char_in_filename = function(name)
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

local byte_to_index_offset = string.byte("a") - 1
---@param node neotree.FileNode
local assign_hotkey = function(node, first_charbyte_counters, jump_labels)
  local first_char = first_char_in_filename(node.name)
  local first_char_byte = first_char:byte()
  local count = first_charbyte_counters[first_char_byte - byte_to_index_offset]
  local hotkey = compute_hotkey(first_char, count, jump_labels)
  first_charbyte_counters[first_char_byte - byte_to_index_offset] = count + 1
  return hotkey
end

-- Generate hotkeys map.
-- Hotkeys will take the first letter of the node name to be the leader,
-- and assign the rest according to the priority of the jump labels in the config.
-- The length is computed dynamiclly.
-- It will be like {leader}{label_1}{label_2}{label_3}......
---@param nodes neotree.FileNode[]
---@param jump_labels string
---@return table<neotree.FileNode, string> node2key
M.assign_hotkeys = function(nodes, jump_labels)
  local node2key = {}

  local first_charbyte_counters = {}
  for c = string.byte("a"), string.byte("z") do
    first_charbyte_counters[c - byte_to_index_offset] = 1
  end

  -- Assign opened buffers more convenient keys.
  local opened_buffers = require("neo-tree.utils").get_opened_buffers()
  local other_nodes = {}
  for _, node in ipairs(nodes) do
    if opened_buffers[node.name] ~= nil then
      node2key[node] = assign_hotkey(node, first_charbyte_counters, jump_labels)
    else
      other_nodes[#other_nodes + 1] = node
    end
  end

  -- Handle the rest.
  for _, node in ipairs(other_nodes) do
    node2key[node] = assign_hotkey(node, first_charbyte_counters, jump_labels)
  end

  return node2key
end

return M
