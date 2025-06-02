---A backend for the clipboard that uses a file in stdpath('state')/neo-tree.nvim/clipboards/ to  sync the clipboard
---.. self.filename
---between everything
local BaseBackend = require("neo-tree.clipboard.sync.base")
local log = require("neo-tree.log")
local uv = vim.uv or vim.loop

---@class neotree.clipboard.FileBackend.Opts
---@field source string
---@field dir string
---@field filename string

local clipboard_states_dir = vim.fn.stdpath("state") .. "/neo-tree.nvim/clipboards"
local pid = vim.uv.os_getpid()

---@class neotree.clipboard.FileBackend.FileFormat
---@field pid integer
---@field time integer
---@field contents neotree.clipboard.Contents

---@class neotree.clipboard.FileBackend : neotree.clipboard.Backend
---@field handle uv.uv_fs_event_t
---@field filename string
---@field source string
---@field pid integer
---@field cached_contents neotree.clipboard.Contents
---@field last_time_saved neotree.clipboard.Contents
---@field saving boolean
local FileBackend = BaseBackend:new()

---@param filename string
---@return boolean created
---@return string? err
local function file_touch(filename)
  if vim.uv.fs_stat(filename) then
    return true
  end
  local dir = vim.fn.fnamemodify(filename, ":h")
  local code = vim.fn.mkdir(dir, "p")
  if code ~= 1 then
    return false, "couldn't make dir" .. dir
  end
  local file, file_err = io.open(filename, "a+")
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

---@param opts neotree.clipboard.FileBackend.Opts?
---@return neotree.clipboard.FileBackend?
function FileBackend:new(opts)
  local backend = {} -- create object if user does not provide one
  setmetatable(backend, self)
  self.__index = self

  -- setup the clipboard file
  opts = opts or {}

  backend.dir = opts.dir or clipboard_states_dir
  local state_source = opts.source or "filesystem"

  local filename = ("%s/%s.json"):format(backend.dir, state_source)

  local success, err = file_touch(filename)
  if not success then
    log.error("Could not make shared clipboard file:", clipboard_states_dir, err)
    return nil
  end

  ---@cast backend neotree.clipboard.FileBackend
  backend.filename = filename
  backend.source = state_source
  backend.pid = pid
  backend:_start()
  return backend
end

---@return boolean started true if working
function FileBackend:_start()
  if self.handle then
    return true
  end
  local event_handle = uv.new_fs_event()
  if event_handle then
    self.handle = event_handle
    local start_success = event_handle:start(self.filename, {}, function(err, _, fs_events)
      if err then
        event_handle:close()
        return
      end
      require("neo-tree.clipboard").sync_to_clipboards()
      -- we should check whether we just wrote or not
    end)
    log.info("Watching " .. self.filename)
    return start_success == 0
  else
    log.warn("could not watch shared clipboard on file events")
    --todo: implement polling?
  end
  return false
end

local typecheck = require("neo-tree.health.typecheck")
local validate = typecheck.validate

---@param wrapped_clipboard neotree.clipboard.FileBackend.FileFormat
local validate_clipboard_from_file = function(wrapped_clipboard)
  return validate("clipboard_from_file", wrapped_clipboard, function(c)
    validate("contents", c.contents, "table")
    validate("pid", c.pid, "number")
    validate("time", c.time, "number")
  end, false, "Clipboard from file could not be validated")
end

function FileBackend:load(state)
  if state.name ~= "filesystem" then
    return nil, nil
  end
  if not file_touch(self.filename) then
    return nil, self.filename .. " could not be created"
  end

  local file, err = io.open(self.filename, "r")
  if not file or err then
    return nil, self.filename .. " could not be opened"
  end
  local content = file:read("*a")
  file:close()
  if vim.trim(content) == "" then
    -- not populated yet, just do nothing
    return nil, nil
  end
  ---@type boolean, neotree.clipboard.FileBackend.FileFormat|any
  local is_success, clipboard_file = pcall(vim.json.decode, content)
  if not is_success then
    local decode_err = clipboard_file
    return nil, "Read failed from shared clipboard file @" .. self.filename .. ":" .. decode_err
  end

  if not validate_clipboard_from_file(clipboard_file) then
    return nil, "could not validate clipboard from file"
  end

  return clipboard_file.contents
end

function FileBackend:save(state)
  if state.name ~= "filesystem" then
    return nil
  end

  local c = state.clipboard
  ---@type neotree.clipboard.FileBackend.FileFormat
  local wrapped = {
    pid = pid,
    time = os.time(),
    contents = c,
  }
  if not file_touch(self.filename) then
    return false, "couldn't write to  " .. self.filename .. self.filename
  end
  local encode_ok, str = pcall(vim.json.encode, wrapped)
  if not encode_ok then
    return false, "couldn't encode clipboard into json"
  end
  local file, err = io.open(self.filename, "w")
  if not file or err then
    return false, "couldn't open " .. self.filename
  end
  local _, write_err = file:write(str)
  if write_err then
    return false, "couldn't write to " .. self.filename
  end
  file:flush()
  file:close()
  return true
end

return FileBackend
