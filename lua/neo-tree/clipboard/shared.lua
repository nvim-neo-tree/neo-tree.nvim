local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local renderer = require("neo-tree.ui.renderer")
local log = require("neo-tree.log")
local uv = vim.uv or vim.loop

---@class neotree.Clipboard.Shared.Opts

local clipboard_states_dir = vim.fn.stdpath("state") .. "/neo-tree.nvim/clipboards"
local pid = vim.uv.os_getpid()

---@class neotree.Clipboard.Shared
---@field handle uv.uv_fs_event_t
---@field filename string
---@field source string
---@field pid integer
local SharedClipboard = {}

---@param filename string
---@param purpose string
local function try_create_file(filename, purpose)
  purpose = purpose or "neo-tree internals"
  local dir = vim.fn.fnamemodify(filename, ":h")
  if not vim.uv.fs_stat(filename) then
    local made_dir, err = vim.fn.mkdir(dir, "p")
    if not made_dir then
      log.error("Could not make directory for ", purpose, ":", err)
      return false
    end
  end
  return true
end

---@param opts neotree.Clipboard.Shared.Opts
---@return neotree.Clipboard.Shared?
function SharedClipboard:new(opts)
  local obj = {} -- create object if user does not provide one
  setmetatable(obj, self)
  self.__index = self

  -- setup the clipboard file
  local state_source = "filesystem" -- could be configurable in the future

  local filename = ("%s/%s.json"):format(clipboard_states_dir, state_source)

  if not vim.uv.fs_stat(filename) then
    local made_dir, err = vim.fn.mkdir(clipboard_states_dir, "p")
    if not made_dir then
      log.error("Could not make shared clipboard directory:", err)
      return nil
    end
  end

  events.subscribe({
    event = events.STATE_CREATED,
    handler = function(state)
      if state.name ~= "filesystem" then
        return
      end
      vim.schedule(function()
        SharedClipboard._update_states(M._load())
      end)
    end,
  })

  obj.filename = filename
  obj.source = state_source
  obj.pid = pid
  table.insert(require("neo-tree.clipboard").shared, obj)
  return obj
end

---@return boolean started true if working
function SharedClipboard:_start()
  if self.handle then
    return true
  end
  local event_handle = uv.new_fs_event()
  if event_handle then
    self.handle = event_handle
    local start_success = event_handle:start(self.filename, {}, function(err, _, fs_events)
      if err then
        log.error("Could not monitor clipboard file, closing")
        event_handle:close()
        return
      end
      self:_update_states(self:_load())
    end)
    return start_success == 0
  else
    log.info("could not watch shared clipboard on file events, trying polling instead")
    -- simulate with uv.new_fs_poll
  end
end

function SharedClipboard:_load()
  local file = io.open(self.filename, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  local is_success, clipboard = pcall(vim.json.decode, content)
  if not is_success then
    local err = clipboard
    log.error("Could not read from shared clipboard file @", self.filename, ":", err)
    return nil
  end
  return clipboard
end

---@param clipboard neotree.Clipboard
function SharedClipboard:save(clipboard)
  local file = io.open(self.filename, "w+")
  -- We want to erase data in the file if clipboard is nil instead writing null
  if not clipboard or not file then
    return
  end

  local encode_ok, data = pcall(vim.json.encode, clipboard)
  if not encode_ok then
    local err = data
    log.error("Failed to save clipboard. JSON serialization error", err)
    return
  end

  local _, write_err = file:write(data)
  if write_err then
    log.error("Saving shared clipboard error", write_err)
  end

  file:flush()
  local close_err = file:close()
  if close_err then
    log.error("Could not close shared clipboard file", write_err)
  end
end

function SharedClipboard:_update_states(clipboard)
  manager._for_each_state("filesystem", function(state)
    state.clipboard = clipboard
    vim.schedule(function()
      renderer.redraw(state)
    end)
  end)
end

return SharedClipboard
