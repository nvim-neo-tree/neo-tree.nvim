local BaseBackend = require("neo-tree.clipboard.sync.base")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local renderer = require("neo-tree.ui.renderer")
local log = require("neo-tree.log")
local uv = vim.uv or vim.loop

---@class neotree.clipboard.FileBackend.Opts
---@field source string

local clipboard_states_dir = vim.fn.stdpath("state") .. "/neo-tree.nvim/clipboards"
local pid = vim.uv.os_getpid()

---@class neotree.clipboard.FileBackend : neotree.clipboard.Backend
---@field handle uv.uv_fs_event_t
---@field filename string
---@field source string
---@field pid integer
local FileBackend = BaseBackend:new()

---@param filename string
---@return boolean created
---@return string? err
local function file_touch(filename)
  local dir = vim.fn.fnamemodify(filename, ":h")
  if vim.uv.fs_stat(filename) then
    return true
  end
  local code = vim.fn.mkdir(dir, "p")
  if code ~= 1 then
    return false, "couldn't make dir" .. dir
  end
  local file, file_err = io.open(dir .. "/" .. filename, "a+")
  if not file then
    return false, file_err
  end

  local _, write_err = file:write("")
  if write_err then
    return false, write_err
  end

  file:flush()
  file:close()
  return true
end

---@param opts neotree.clipboard.FileBackend.Opts
---@return neotree.clipboard.FileBackend?
function FileBackend:new(opts)
  local obj = {} -- create object if user does not provide one
  setmetatable(obj, self)
  self.__index = self

  -- setup the clipboard file
  local state_source = opts.source or "filesystem" -- could be configurable in the future

  local filename = ("%s/%s.json"):format(clipboard_states_dir, state_source)

  local success, err = file_touch(filename)
  if not success then
    log.error("Could not make shared clipboard file:", clipboard_states_dir, err)
    return nil
  end

  obj.filename = filename
  obj.source = state_source
  obj.pid = pid
  return obj
end

---@return boolean started true if working
function FileBackend:_start()
  if self.handle then
    return true
  end
  -- monitor the file and make sure it doesn't update neo-tree
  local event_handle = uv.new_fs_event()
  if event_handle then
    self.handle = event_handle
    local start_success = event_handle:start(self.filename, {}, function(err, _, fs_events)
      if err then
        log.error("Could not monitor clipboard file, closing")
        event_handle:close()
        return
      end
    end)
    return start_success == 0
  else
    log.info("could not watch shared clipboard on file events")
  end
  return false
end

function FileBackend:load()
  if not file_touch(self.filename) then
    return nil, self.filename .. " could not be created"
  end
  local file, err = io.open(self.filename, "r")
  if not file or err then
    return nil, self.filename .. " could not be opened"
  end
  local content = file:read("*a")
  ---@type boolean, neotree.clipboard.FileBackend.FileFormat|any
  local is_success, clipboard = pcall(vim.json.decode, content)
  if not is_success then
    local decode_err = clipboard
    local msg = "Read failed from shared clipboard file @" .. self.filename .. ":" .. decode_err
    log.error(msg)
    return nil, msg
  end

  if not clipboard then
    return nil, nil
  end

  return clipboard.contents
end

---@class neotree.clipboard.FileBackend.FileFormat
---@field pid integer
---@field time integer
---@field contents neotree.clipboard.Contents

function FileBackend:save(state)
  local clipboard = state.clipboard
  ---@type neotree.clipboard.FileBackend.FileFormat
  local wrapped = {
    pid = pid,
    time = os.time(),
    contents = clipboard,
  }
  local encode_ok, str = pcall(vim.json.encode, wrapped)
  if not encode_ok then
    log.error("Could not write error")
  end
  if not file_touch(self.filename) then
    return false
  end
  local file, err = io.open(self.filename, "w")
  if not file or err then
    return false
  end
  local _, write_err = file:write(str)
  if write_err then
    return false
  end
  file:flush()
  file:close()
  return true
end

return FileBackend
