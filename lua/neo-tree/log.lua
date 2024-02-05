-- log.lua
--
-- Inspired by rxi/log.lua
-- Modified by tjdevries and can be found at github.com/tjdevries/vlog.nvim
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.

-- User configuration section
---@class NeotreeLogConfig
local default_config = {
  -- Name of the plugin. Prepended to log messages
  plugin = "neo-tree.nvim",

  -- Should print the output to neovim while running
  use_console = true,

  -- Should highlighting be used in console (using echohl)
  highlights = true,

  -- Should write to a file
  use_file = false,

  -- Any messages above this level will be logged.
  ---@type string
  level = "info",

  -- Level configuration
  ---@type NeotreeLogLevel[]
  modes = {
    { name = "trace", hl = "None", level = vim.log.levels.TRACE },
    { name = "debug", hl = "None", level = vim.log.levels.DEBGUG },
    { name = "info", hl = "None", level = vim.log.levels.INFO },
    { name = "warn", hl = "WarningMsg", level = vim.log.levels.WARN },
    { name = "error", hl = "ErrorMsg", level = vim.log.levels.ERROR },
    { name = "fatal", hl = "ErrorMsg", level = vim.log.levels.ERROR },
  },

  -- Can limit the number of decimals displayed for floats
  float_precision = 0.01,
}

local unpack = unpack or table.unpack
---Round float at a certain precision
---@param x number
---@param increment number # The smallest digit where `x` will be rounded. `0.1` will output `nn.n`.
---@return number
local round = function(x, increment)
  increment = increment or 1
  x = x / increment
  return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
end

---@class NeotreeLogLevel
---@field name string # Name of the log level
---@field hl NeotreeConfig.highlight # Highlight group to use to notify
---@field level integer # One of `vim.log.levels`

---@alias NeotreeLogFunc fun(...: string|integer|boolean)
---@alias NeotreeLogFmt "fmt_trace"|"fmt_debug"|"fmt_info"|"fmt_warn"|"fmt_error"|"fmt_fatal"

---@class NeotreeLog
---@field _use_file boolean|nil
---@field outfile NeotreePathString
---@field config NeotreeLogConfig
---@field level table<string, integer>
---@field [NeotreeConfig.log_level] NeotreeLogFunc
---@field [NeotreeLogFmt] NeotreeLogFunc
local log = {}

---Wrapper function for `vim.notify` to add opts when possible.
---@param message string
---@param level_config NeotreeLogLevel
local notify = function(message, level_config)
  if type(vim.notify) == "table" then
    -- probably using nvim-notify
    vim.notify(message, level_config.level, { title = "Neo-tree" })
  else
    local nameupper = level_config.name:upper()
    local console_string = string.format("[Neo-tree %s] %s", nameupper, message)
    vim.notify(console_string, level_config.level)
  end
end

---Set or unset file to output logs.
---@param file NeotreePathString|boolean # If false, unsets file, or set to file. If true, uses default path.
---@param quiet boolean|nil # If true, logs when file is set.
log.use_file = function(file, quiet)
  error(string.format("Neotree log: call `log.new` first. %s, %s", file, quiet))
end

---Set log level.
---@param level string # Any messages above this level will be logged.
log.set_level = function(level)
  error(string.format("Neotree log: call `log.new` first. %s", level))
end

---Initiate a log instance.
---@param config NeotreeLogConfig
---@param standalone boolean # If true, returns a global log object that is shared among others.
log.new = function(config, standalone)
  ---@class NeotreeLog
  local obj = log
  if not standalone then
    obj = setmetatable({}, log)
    obj.__index = log
  end
  obj.outfile = string.format("%s/%s.log", vim.fn.stdpath("data"), config.plugin)
  ---@class NeotreeLogConfig
  obj.config = vim.tbl_deep_extend("force", default_config, config)
  obj.levels = {}
  for i, v in ipairs(obj.config.modes) do
    obj.levels[v.name] = i
  end
  obj.use_file = function(file, quiet)
    obj.config.use_file = file ~= false ---@diagnostic disable-line
    if file == false then
      if not quiet then
        obj.info("[neo-tree] Logging to file disabled")
      end
    else
      if not quiet then
        obj.info("[neo-tree] Logging to file: " .. obj.outfile)
      end
      if type(file) == "string" then
        obj.outfile = file
      end
    end
  end
  obj.set_level = function(level)
    if obj.levels[level] then
      if obj.config.level ~= level then
        obj.config.level = level
      end
    else
      notify("Invalid log level: " .. level, obj.config.modes[5])
    end
  end

  local make_string = function(...)
    local t = {}
    for i = 1, select("#", ...) do
      local x = select(i, ...)

      if type(x) == "number" and obj.config.float_precision then
        x = tostring(round(x, obj.config.float_precision))
      elseif type(x) == "table" then
        x = vim.inspect(x)
        if #x > 300 then
          x = x:sub(1, 300) .. "..."
        end
      else
        x = tostring(x)
      end

      t[#t + 1] = x
    end
    return table.concat(t, " ")
  end

  ---Decide whether to log
  ---@param level integer # index in `obj.levels`
  ---@param level_config NeotreeLogLevel
  ---@param message_maker fun(...): string
  ---@vararg ... string|integer|number|boolean|nil
  local log_at_level = function(level, level_config, message_maker, ...)
    -- Return early if we're below the config.level
    if level < obj.levels[obj.config.level] then
      return
    end
    -- Ignnore this if vim is exiting
    if vim.v.dying > 0 or vim.v.exiting ~= vim.NIL then
      return
    end
    local nameupper = level_config.name:upper()

    local msg = message_maker(...)
    local info = debug.getinfo(2, "Sl")
    local lineinfo = info.short_src .. ":" .. info.currentline
    if obj.config.use_file then
      local str = string.format("[%-6s%s] %s: %s\n", nameupper, os.date(), lineinfo, msg)
      local fp = io.open(obj.outfile, "a")
      if fp then
        fp:write(str)
        fp:close()
      else
        print("[neo-tree] Could not open log file: " .. obj.outfile)
      end
    end
    if obj.config.use_console and level > 2 then
      vim.schedule(function()
        notify(msg, level_config)
      end)
    end
  end

  for i, x in ipairs(obj.config.modes) do
    obj[x.name] = function(...)
      return log_at_level(i, x, make_string, ...)
    end
    obj["fmt_" .. x.name] = function()
      return log_at_level(i, x, function(...)
        local passed = { ... }
        local fmt = table.remove(passed, 1)
        local inspected = {}
        for _, v in ipairs(passed) do
          table.insert(inspected, vim.inspect(v))
        end
        return string.format(fmt, unpack(inspected))
      end)
    end
  end

  return obj
end

log.new(default_config, true)

return log
