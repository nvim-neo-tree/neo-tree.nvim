---A backend for the clipboard that uses a file in stdpath('state')/neo-tree.nvim/clipboards/ .. self.filename
---to sync the clipboard between everything.
local Backend = require("neo-tree.clipboard.sync.base")
local log = require("neo-tree.log").new("clipboard")
local uv = vim.uv or vim.loop

---@class neotree.clipboard.FileBackend.Opts
---@field source string
---@field dir string
---@field filename string

local clipboard_states_dir = vim.fn.stdpath("state") .. "/neo-tree.nvim/clipboards"
local pid = uv.os_getpid()

---@class (exact) neotree.clipboard.FileBackend.FileFormat
---@field pid integer
---@field state_name string
---@field contents neotree.clipboard.Contents

---@class neotree.clipboard.FileBackend : neotree.clipboard.Backend
---@field dir string
---@field handle uv.uv_fs_event_t
---@field filename string
---@field source string
---@field pid integer
---@field cached_contents neotree.clipboard.Contents
---@field last_stat_seen uv.fs_stat.result?
---@field saving boolean
local UniversalBackend = Backend:new()

---@param filename string
---@return uv.fs_stat.result? stat
---@return string? err
local function file_touch(filename)
  local stat = uv.fs_stat(filename)
  if stat then
    return stat
  end
  local dir = vim.fn.fnamemodify(filename, ":h")
  local mkdir_ok = vim.fn.mkdir(dir, "p")
  if mkdir_ok == 0 then
    return nil, "couldn't make dir " .. dir
  end
  local file, file_err = io.open(filename, "a+")
  if not file then
    return nil, file_err
  end

  local _, write_err = file:write("")
  if write_err then
    return nil, write_err
  end

  file:flush()
  file:close()
  return uv.fs_stat(filename)
end

---@param opts neotree.clipboard.FileBackend.Opts?
---@return neotree.clipboard.FileBackend?
function UniversalBackend:new(opts)
  local backend = {}
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

  backend.filename = filename
  backend.source = state_source
  backend.pid = pid
  if not backend:_start() then
    return nil
  end
  return backend
end

---@return boolean started true if working
function UniversalBackend:_start()
  if self.handle then
    return true
  end
  local event_handle = uv.new_fs_event()
  if event_handle then
    self.handle = event_handle
    local start_success = event_handle:start(self.filename, {}, function(err)
      if err then
        log.error("universal clipboard file handle error:", err)
        event_handle:close()
        return
      end
      require("neo-tree.clipboard").sync_to_clipboards()
      -- we should check whether we just wrote or not
    end)
    log.debug("Watching", self.filename)
    return start_success == 0
  else
    log.warn("Could not watch shared clipboard on file events")
    --todo: implement polling?
  end
  return false
end

local typecheck = require("neo-tree.health.typecheck")
local validate = typecheck.validate

function UniversalBackend:save(state)
  if state.name ~= "filesystem" then
    return nil
  end

  ---@type neotree.clipboard.FileBackend.FileFormat
  local wrapped = {
    pid = pid,
    state_name = assert(state.name),
    contents = state.clipboard,
  }
  local touch_ok, err = file_touch(self.filename)
  if not touch_ok then
    return false, "Couldn't write to  " .. self.filename .. ":" .. err
  end
  local encode_ok, str = pcall(vim.json.encode, wrapped)
  if not encode_ok then
    local encode_err = str
    return false, "Couldn't encode clipboard into json: " .. encode_err
  end
  local file, open_err = io.open(self.filename, "w")
  if not file then
    return false, "Couldn't open " .. self.filename .. ": " .. open_err
  end
  local _, write_err = file:write(str)
  if write_err then
    return false, "Couldn't write to " .. self.filename .. ": " .. write_err
  end
  file:flush()
  self.last_stat_seen = log.assert(uv.fs_stat(self.filename))
  self.last_clipboard_saved = state.clipboard
  return true
end

---@param wrapped_clipboard neotree.clipboard.FileBackend.FileFormat
local validate_clipboard_from_file = function(wrapped_clipboard)
  return validate("clipboard_from_file", wrapped_clipboard, function(c)
    validate("contents", c.contents, "table")
    validate("pid", c.pid, "number")
    validate("state_name", c.state_name, "string")
  end, false, "Clipboard from file could not be validated")
end

function UniversalBackend:load(state)
  if state.name ~= "filesystem" then
    return nil, nil
  end
  local stat = uv.fs_stat(self.filename)
  if stat and self.last_stat_seen then
    if stat.mtime == self.last_stat_seen.mtime then
      log.debug("Using cached clipboard from ", stat.mtime)
      return self.last_clipboard_saved
    end
  end
  self.last_stat_seen = stat
  local file_ok, touch_err = file_touch(self.filename)
  if not file_ok then
    return nil, touch_err
  end

  local file, err = io.open(self.filename, "r")
  if not file or err then
    return nil, self.filename .. " could not be opened"
  end

  ---@type string
  local content = file:read("*a")
  file:close()
  content = vim.trim(content)
  if content == "" then
    -- not populated yet, just do nothing
    return nil, nil
  end
  ---@type boolean, neotree.clipboard.FileBackend.FileFormat|any
  local is_success, saved_clipboard = pcall(vim.json.decode, content)
  if not is_success then
    local decode_err = saved_clipboard
    return nil,
      ("JSON decode from universal clipboard file @ %s failed: decode_err"):format(
        self.filename,
        decode_err
      )
  end

  if not validate_clipboard_from_file(saved_clipboard) then
    if
      require("neo-tree.ui.inputs").confirm(
        "Neo-tree clipboard file seems invalid, clear out clipboard?"
      )
    then
      local success, delete_err = os.remove(self.filename)
      if not success then
        log.error(delete_err)
      end

      -- clear out current state clipboard
      state.clipboard = {}
      local ok, save_err = self:save(state)
      if ok == false then
        log.error(save_err)
      end
      return {}
    end
    return nil, "Could not parse a valid clipboard from clipboard file"
  end

  return saved_clipboard.contents
end

return UniversalBackend
