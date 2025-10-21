---A backend for the clipboard that uses a file in stdpath('state')/neo-tree.nvim/clipboards/ .. self.filename
---to sync the clipboard between everything.
local Backend = require("neo-tree.clipboard.sync.base")
local log = require("neo-tree.log").new("clipboard")
local validate = require("neo-tree.health.typecheck").validate
local uv = vim.uv or vim.loop
local utils = require("neo-tree.utils")

---@class neotree.clipboard.FileBackend.Opts
---@field source string
---@field dir string
---@field filename string

local clipboard_states_dir = vim.fn.stdpath("state") .. "/neo-tree.nvim/clipboards"

---@class (exact) neotree.clipboard.FileBackend.FileFormat
---@field state_name string
---@field contents neotree.clipboard.Contents

---@class neotree.clipboard.FileBackend : neotree.clipboard.Backend
---@field paths table<string, string?>
---@field dir string
---@field handles table<string, uv.uv_handle_t>
---@field cached_contents neotree.clipboard.Contents
---@field last_stat_seen uv.fs_stat.result?
---@field saving boolean
local UniversalBackend = Backend:new()

---@param filename string
---@return boolean? stat
---@return string? err
local function file_touch(filename, mkdir)
  local dir = vim.fn.fnamemodify(filename, ":h")
  local mkdir_ok = vim.fn.mkdir(dir, "p")
  if mkdir_ok == 0 then
    return nil, "couldn't make dir " .. dir
  end

  local file, file_err = io.open(filename, "w")
  if not file then
    return nil, file_err
  end

  file:flush()
  file:close()
  return true
end

---@param opts neotree.clipboard.FileBackend.Opts?
---@return neotree.clipboard.FileBackend?
function UniversalBackend:new(opts)
  local backend = {}
  setmetatable(backend, self)
  self.__index = self

  -- setup the clipboard file
  opts = opts or {}
  self.handles = {}

  backend.dir = opts.dir or clipboard_states_dir
  return backend
end

---@param filename string
---@return uv.uv_fs_event_t? started true if working
function UniversalBackend:_watch_file(filename)
  local event_handle = uv.new_fs_event()
  if not event_handle then
    log.warn("Could not watch shared clipboard on file events")
    return nil
  end

  local start_success = event_handle:start(filename, {}, function(err)
    if err then
      log.error("File handle error:", err, ", syncing will be disabled")
      event_handle:close()
      return
    end

    local stat = uv.fs_stat(filename)
    if not stat then
      log.warn("Clipboard file", filename, "was replaced or deleted")
      self.handles[filename] = nil
      event_handle:close()
      return
    end

    local last_write_from_here = self.saving or stat.mtime.nsec == self.last_stat_seen.mtime.nsec
    self.last_stat_seen = stat
    if last_write_from_here then
      return
    end

    require("neo-tree.clipboard").update_states()
  end)
  log.debug("Watching", filename)
  local handle = start_success and event_handle
  self.handles[filename] = handle
  return handle
end

do
  local cache = {}
  function UniversalBackend:get_filename(state)
    local cached = cache[state.name]
    if cached then
      return cached
    end

    local fname = utils.path_join(self.dir, state.name .. ".json")
    cache[state.name] = fname
    return fname
  end
end

function UniversalBackend:save(state)
  ---@type neotree.clipboard.FileBackend.FileFormat
  local wrapped = {
    state_name = assert(state.name),
    contents = state.clipboard,
  }
  local filename = self:get_filename(state)

  if not uv.fs_stat(filename) then
    local touch_ok, err = file_touch(filename)
    if not touch_ok then
      return false, "Couldn't write to " .. filename .. ":" .. err
    end
  end

  local encode_ok, str = pcall(vim.json.encode, wrapped)
  if not encode_ok then
    local encode_err = str
    return false, "Couldn't encode clipboard into json: " .. encode_err
  end

  local file, open_err = io.open(filename, "w")
  if not file then
    return false, "Couldn't open " .. filename .. ": " .. open_err
  end

  self.saving = true
  local _, write_err = file:write(str)
  file:flush()
  if write_err then
    self.saving = false
    return false, "Couldn't write to " .. filename .. ": " .. write_err
  end

  self.last_stat_seen = log.assert(uv.fs_stat(filename))
  self.last_clipboard_saved = state.clipboard
  self.saving = false
  return true
end

---@param wrapped_clipboard neotree.clipboard.FileBackend.FileFormat
local validate_clipboard_from_file = function(wrapped_clipboard)
  return validate("clipboard_from_file", wrapped_clipboard, function(c)
    validate("contents", c.contents, "table")
    validate("state_name", c.state_name, "string")
  end, false, "Clipboard from file could not be validated", function() end)
end

function UniversalBackend:load(state)
  local filename = self:get_filename(state)
  local stat = uv.fs_stat(filename)
  if stat and self.last_stat_seen then
    if stat.mtime == self.last_stat_seen.mtime then
      log.debug("Using cached clipboard from", stat.mtime)
      return self.last_clipboard_saved
    end
  end
  self.last_stat_seen = stat

  if not stat then
    local file_ok, touch_err = file_touch(filename)
    if not file_ok then
      return nil, touch_err
    end
  end

  local handle = self.handles[filename]
  if not handle then
    self:_watch_file(filename)
  elseif not handle:is_active() then
    log.debug("Handle for", filename, "is dead")
  end

  local file, err = io.open(filename, "r")
  if not file then
    return nil, filename .. " could not be opened: " .. err
  end

  ---@type string
  local content = file:read("*a")
  file:close()
  content = vim.trim(content)
  if content == "" then
    -- not populated yet, just do nothing
    return nil
  end
  ---@type boolean, neotree.clipboard.FileBackend.FileFormat|any
  local is_success, saved_clipboard = pcall(vim.json.decode, content)
  if not is_success or not validate_clipboard_from_file(saved_clipboard) then
    log.debug("Clipboard file", filename, "looks to be invalid", saved_clipboard)
    if
      require("neo-tree.ui.inputs").confirm(
        "Neo-tree universal clipboard file for "
          .. state.name
          .. " seems invalid, clear out clipboard?"
      )
    then
      local success, delete_err = os.remove(filename)
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
