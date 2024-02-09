local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local Queue = require("neo-tree.collections").Queue

local event_queues = {}

---@alias NeotreeEventOpts table

local event_definitions = {}

---@class NeotreeEventQueue
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
  for event_name, _ in pairs(event_queues) do
    M.destroy_event(event_name)
  end
  event_queues = {}
end

---Assign new event. Skips if event already exists.
M.define_event = function(event_name, opts)
  local existing = event_definitions[event_name]
  if existing ~= nil then
    error("Event already defined: " .. event_name)
  end
  event_definitions[event_name] = opts
end

---Delete event.
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
  if event_queues[event_name] then
    Queue.clear(event_queues[event_name])
  end
  event_queues[event_name] = nil
  return true
end

---Fire event.
local fire_event_internal = function(event, args)
  local queue = event_queues[event]
  if queue == nil then
    return nil
  end

  if Queue.is_empty(queue) then
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

  local run_each_handler = function(event_handler)
    if event_handler and not event_handler.cancelled then
      local success, result = pcall(event_handler.handler, args)
      local id = event_handler.id or event_handler
      if success then
        log.trace("Handler ", id, " for " .. event .. " called successfully.")
      else
        log.error(string.format("Error in event handler for event %s[%s]: %s", event, id, result))
      end
      if event_handler.once then
        event_handler.cancelled = true
        return true
      end
      return result
    end
    return false
  end
  return Queue.for_each(queue, run_each_handler)
end

---Fire events assigned to event_name.
M.fire_event = function(event_name, args)
  local def = event_definitions[event_name]
  local freq = def and def.debounce_frequency or 0
  local strategy = def and def.debounce_strategy or 0
  log.trace("Firing event: ", event_name, " with args: ", args)
  if freq > 0 then
    utils.debounce("EVENT_FIRED: " .. event_name, function()
      fire_event_internal(event_name, args or {})
    end, freq, strategy)
  else
    return fire_event_internal(event_name, args or {})
  end
end

---Add a new event_handler
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
  Queue.add(queue, event_handler)
end

M.unsubscribe = function(event_handler)
  local queue = event_queues[event_handler.event]
  if queue == nil then
    return nil
  end
  Queue.remove_by_id(queue, event_handler.id or event_handler)
  if Queue.is_empty(queue) then
    M.destroy_event(event_handler.event)
  end
end

return M
