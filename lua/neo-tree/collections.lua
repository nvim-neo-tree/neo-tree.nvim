local log = require("neo-tree.log")
---@class NeotreeCollections
local M = {}

---@class NeotreeListNode
M.Node = {}

---Create new NeotreeListNode of type <T>
function M.Node:new(value)
  local props = { prev = nil, next = nil, value = value }
  setmetatable(props, self)
  self.__index = self
  return props
end

---@class NeotreeLinkedList
M.LinkedList = {}
function M.LinkedList:new()
  local props = { head = nil, tail = nil, size = 0 }
  setmetatable(props, self)
  self.__index = self
  return props
end

---Add NeotreeListNode into linked list
function M.LinkedList:add_node(node)
  if self.head == nil then
    self.head = node
    self.tail = node
  else
    self.tail.next = node
    node.prev = self.tail
    self.tail = node
  end
  self.size = self.size + 1
  return node
end

---Remove NeotreeListNode from a linked list
function M.LinkedList:remove_node(node)
  if node.prev ~= nil then
    node.prev.next = node.next
  end
  if node.next ~= nil then
    node.next.prev = node.prev
  end
  if self.head == node then
    self.head = node.next
  end
  if self.tail == node then
    self.tail = node.prev
  end
  self.size = self.size - 1
  node.prev = nil
  node.next = nil
  node.value = nil
end

---Clear all nodes in the list
function M.LinkedList:clear()
  local current = self.head
  while current ~= nil do
    local next = current.next
    self:remove_node(current)
    current = next
  end
end

---@class NeotreeQueue
---@field _list NeotreeLinkedList
M.Queue = {}

function M.Queue:new()
  local props = {}
  props._list = M.LinkedList:new()
  setmetatable(props, self)
  self.__index = self ---@diagnostic disable-line
  return props
end

---Add an element to the end of the queue.
function M.Queue:add(value)
  self._list:add_node(M.Node:new(value))
end

---Iterates over the entire list, running func(value) on each element.
---If func returns true, the element is removed from the list.
function M.Queue:for_each(func)
  local node = self._list.head
  while node ~= nil do
    local result = func(node.value)
    if type(result) == "table" then
      if result.handled == true then
        local id = node.value.id or nil ---@diagnostic disable-line
        local event = node.value.event or nil ---@diagnostic disable-line
        log.trace(
          string.format(
            "Handler %s for %s returned handled = true, skipping the rest of the queue.",
            id,
            event
          )
        )
        return result
      end
    end
    if result == true then
      local next = node.next
      self._list:remove_node(node)
      node = next
    else
      node = node.next
    end
  end
end

function M.Queue:is_empty()
  return self._list.size == 0
end

function M.Queue:remove_by_id(id)
  local current = self._list.head
  while current ~= nil do
    local item = current.value
    local item_id = type(item) == "table" and item.id or item
    if item_id == id then
      local next = current.next
      self._list:remove_node(current)
      current = next
    else
      current = current.next
    end
  end
end

function M.Queue:clear()
  self._list:clear()
end

return M
