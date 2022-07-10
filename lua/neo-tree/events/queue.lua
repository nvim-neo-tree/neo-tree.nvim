local utils = require("neo-tree.utils")
local log = require("neo-tree.log")

Node = {}
function Node:new(value)
  local props = { prev = nil, next = nil, value = value }
  setmetatable(props, self)
  self.__index = self
  return props
end

LinkedList = {}
function LinkedList:new()
  local props = { head = nil, tail = nil, size = 0 }
  setmetatable(props, self)
  self.__index = self
  return props
end

function LinkedList:add_node(node)
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

function LinkedList:remove_node(node)
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

-- First in Last Out
Queue = {}
function Queue:new()
  local props = { _list = LinkedList:new() }
  setmetatable(props, self)
  self.__index = self
  return props
end

---Add an element to the end of the queue.
---@param value any The value to add.
function Queue:add(value)
  self._list:add_node(Node:new(value))
end

---Iterates over the entire list, running func(value) on each element.
---If func returns true, the element is removed from the list.
---@param func function The function to run on each element.
function Queue:for_each(func)
  local node = self._list.head
  while node ~= nil do
    local remove_node = func(node.value)
    if remove_node then
      local node_to_remove = node
      node = node.next
      self._list:remove_node(node_to_remove)
    else
      node = node.next
    end
  end
end

function Queue:is_empty()
  return self._list.size == 0
end

function Queue:remove_by_id(id)
  local current = self._list.head
  while current ~= nil do
    local is_match = false
    local item = current.value
    if item ~= nil then
      local item_id = item.id or item
      if item_id == id then
        is_match = true
      end
    end
    if is_match then
      local next = current.next
      self._list:remove_node(current)
      current = next
    else
      current = current.next
    end
  end
end

local event_queues = {}
local event_definitions = {}
local M = {}

local validate_event_handler = function(event_handler)
  if type(event_handler) ~= "table" then
    error("Event handler must be a table")
  end
  if type(event_handler.event) ~= "string" then
    error("Event handler must have an event")
  end
  if type(event_handler.handler) ~= "function" then
    error("Event handler must have a handler")
  end
end

M.clear_all_events = function()
  for event_name, queue in pairs(event_queues) do
    M.destroy_event(event_name)
  end
  event_queues = {}
end

M.define_event = function(event_name, opts)
  local existing = event_definitions[event_name]
  if existing ~= nil then
    error("Event already defined: " .. event_name)
  end
  event_definitions[event_name] = opts
end

M.destroy_event = function(event_name)
  local existing = event_definitions[event_name]
  if existing == nil then
    return false
  end
  if existing.setup_was_run and type(existing.teardown) == "function" then
    local success, result = pcall(existing.teardown)
    if not success then
      error("Error in teardown for " .. event_name .. ": " .. result)
    end
    existing.setup_was_run = false
  end
  event_queues[event_name] = nil
  return true
end

local fire_event_internal = function(event, args)
  local queue = event_queues[event]
  if queue == nil then
    return nil
  end
  --log.trace("Firing event: ", event, " with args: ", args)

  if queue:is_empty() then
    --log.trace("Event queue is empty")
    return nil
  end
  local seed = utils.get_value(event_definitions, event .. ".seed")
  if seed ~= nil then
    local success, result = pcall(seed, args)
    if success and result then
      log.trace("Seed for " .. event .. " returned: " .. tostring(result))
    elseif success then
      log.trace("Seed for " .. event .. " returned falsy, cancelling event")
    else
      log.error("Error in seed function for " .. event .. ": " .. result)
    end
  end

  queue:for_each(function(event_handler)
    local remove_node = event_handler == nil or event_handler.cancelled
    if not remove_node then
      local success, result = pcall(event_handler.handler, args)
      local id = event_handler.id or event_handler
      if success then
        log.trace("Handler ", id, " for " .. event .. " called successfully.")
        if
          type(result) == "table"
          and type(result.handled) == "boolean"
          and result.handled == true
        then
          log.trace(
            "Handler ",
            id,
            " for " .. event .. " returned handled = true, skipping the rest of the queue."
          )
          return result
        end
      else
        log.error(string.format("Error in event handler for event %s[%s]: %s", event, id, result))
      end
      if event_handler.once then
        event_handler.cancelled = true
        remove_node = true
      end
    end
    return remove_node
  end)
end

M.fire_event = function(event, args)
  local freq = utils.get_value(event_definitions, event .. ".debounce_frequency", 0, true)
  local strategy = utils.get_value(event_definitions, event .. ".debounce_strategy", 0, true)
  log.trace("Firing event: ", event, " with args: ", args)
  if freq > 0 then
    utils.debounce("EVENT_FIRED: " .. event, function()
      fire_event_internal(event, args or {})
    end, freq, strategy)
  else
    return fire_event_internal(event, args or {})
  end
end

M.subscribe = function(event_handler)
  validate_event_handler(event_handler)

  local queue = event_queues[event_handler.event]
  if queue == nil then
    log.debug("Creating queue for event: " .. event_handler.event)
    queue = Queue:new()
    local def = event_definitions[event_handler.event]
    if def and type(def.setup) == "function" then
      local success, result = pcall(def.setup)
      if success then
        def.setup_was_run = true
        log.debug("Setup for event " .. event_handler.event .. " was run")
      else
        log.error("Error in setup for " .. event_handler.event .. ": " .. result)
      end
    end
    event_queues[event_handler.event] = queue
  end
  log.debug("Adding event handler [", event_handler.id, "] for event: ", event_handler.event)
  queue:add(event_handler)
end

M.unsubscribe = function(event_handler)
  local queue = event_queues[event_handler.event]
  if queue == nil then
    return nil
  end
  queue:remove_by_id(event_handler.id or event_handler)
  if queue:is_empty() then
    M.destroy_event(event_handler.event)
    event_queues[event_handler.event] = nil
  else
    event_queues[event_handler.event] = queue
  end
end

return M
