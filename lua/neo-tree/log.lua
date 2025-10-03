---@enum neotree.Log.Levels
local Levels = {
  TRACE = 0,
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
  FATAL = 5,
}
local uv = vim.uv or vim.loop
-- log.lua
--
-- Inspired by rxi/log.lua
-- Modified by tjdevries and can be found at github.com/tjdevries/vlog.nvim
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.

---@alias neotree.Log.Level
---|neotree.Log.Levels
---|"trace"
---|"debug"
---|"info"
---|"warn"
---|"error"
---|"fatal"

---@alias neotree.Logger.Config.Level neotree.Logger.Config.ConsoleAndFileLevel|neotree.Log.Level

---@class neotree.Logger.Config.ConsoleAndFileLevel
---@field console neotree.Log.Level
---@field file neotree.Log.Level

---@class neotree.Logger.Config
---@type neotree.Logger.Config
local default_config = {
  -- Name of the plugin. Prepended to log messages
  ---@type string
  plugin = "neo-tree.nvim",

  plugin_short = "Neo-tree",

  ---@type string[]
  context = {},

  ---Should print the output to neovim while running
  ---@type boolean
  use_console = true,

  ---Should highlighting be used in console (using echohl)
  ---@type boolean
  highlights = true,

  ---@type boolean
  use_file = false,

  ---@type table<vim.log.levels, neotree.Logger.LevelConfig>
  level_configs = {
    [Levels.TRACE] = { name = "trace", hl = "None" },
    [Levels.DEBUG] = { name = "debug", hl = "None" },
    [Levels.INFO] = { name = "info", hl = "None" },
    [Levels.WARN] = { name = "warn", hl = "WarningMsg" },
    [Levels.ERROR] = { name = "error", hl = "ErrorMsg" },
    [Levels.FATAL] = { name = "fatal", hl = "ErrorMsg" },
  },

  ---Any messages above this level will be logged.
  ---@type neotree.Logger.Config.ConsoleAndFileLevel
  level = {
    file = vim.log.levels.INFO,
    console = vim.log.levels.INFO,
  },

  -- Can limit the number of decimals displayed for floats
  ---@type number
  float_precision = 0.01,
}

local log_maker = {}

---@class (partial) neotree.Logger.PartialConfig : neotree.Logger.Config
---@param config neotree.Logger.PartialConfig|neotree.Logger.Config
---@return neotree.Logger
log_maker.new = function(config)
  ---@class neotree.Logger
  local log = {}
  ---@diagnostic disable-next-line: cast-local-type
  config = vim.tbl_deep_extend("force", default_config, config)

  local title_opts = { title = config.plugin_short }
  ---@param message string
  ---@param level vim.log.levels
  local notify = vim.schedule_wrap(function(message, level)
    if type(vim.notify) == "table" then
      -- probably using nvim-notify
      vim.notify(message, level, title_opts)
    else
      local level_config = config.level_configs[level]
      local console_string = ("[%s %s] %s"):format(
        config.plugin_short,
        level_config.name:upper(),
        message
      )
      vim.notify(console_string, level)
    end
  end)

  local initial_filepath = string.format("%s/%s.log", vim.fn.stdpath("data"), config.plugin)

  ---@type file*?
  log.file = nil
  if config.use_file then
    log.use_file(initial_filepath)
  end

  local round = function(x, increment)
    increment = increment or 1
    x = x / increment
    return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
  end

  local last_logfile_check_time = 0
  local current_logfile_inode = -1
  local logfile_check_interval = 20 -- TODO: probably use filesystem events rather than this
  local inspect_opts = { depth = 2, newline = " " }
  local prefix = table.concat(config.context, ".")
  ---@param log_type string
  ---@param msg string
  local log_to_file = function(log_type, msg)
    local info = debug.getinfo(3, "Sl")
    local lineinfo = info.short_src .. ":" .. info.currentline
    local str =
      string.format("[%-6s%s] %s%s: %s\n", log_type, os.date("%F-%T"), prefix, lineinfo, msg)
    if log.file and assert(log.file:write(str)) then
      local curtime = os.time()
      -- make sure the file is valid every so often
      if os.difftime(curtime, last_logfile_check_time) >= logfile_check_interval then
        last_logfile_check_time = curtime
        log.use_file(log.outfile, true)
      end
      return
    end

    vim.schedule(function()
      vim.notify_once("[neo-tree] Could not open log file: " .. log.outfile)
    end)
  end

  ---@type { file: vim.log.levels, console: vim.log.levels }
  log.minimum_level = nil

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if log.file then
        log.file:close()
      end
    end,
  })

  local make_string = function(...)
    local tbl = {}
    for i = 1, select("#", ...) do
      local x = select(i, ...)

      local _type = type(x)
      if _type ~= "string" then
        if _type == "number" and config.float_precision then
          x = tostring(round(x, config.float_precision))
        elseif _type == "table" then
          x = vim.inspect(x, inspect_opts)
          if #x > 300 then
            x = x:sub(1, 300) .. "..."
          end
        else
          x = tostring(x)
        end
      end

      tbl[#tbl + 1] = x
    end
    return table.concat(tbl, " ")
  end
  ---@alias neotree.LogFunction fun(...)

  ---@return neotree.LogFunction
  ---@param log_level vim.log.levels
  ---@param message_maker fun(...):string
  local logfunc = function(log_level, message_maker)
    if log_level < log.minimum_level.file and log_level < log.minimum_level.console then
      return function() end
    end
    local level_config = config.level_configs[log_level]
    local name_upper = level_config.name:upper()
    return function(...)
      -- Return early if we're below the config.level
      -- Ignore this if vim is exiting
      if vim.v.dying > 0 or vim.v.exiting ~= vim.NIL then
        return
      end

      local msg = message_maker(...)

      -- Output to log file
      if config.use_file and log_level >= log.minimum_level.file then
        log_to_file(name_upper, msg)
      end

      -- Output to console
      if config.use_console and log_level >= log.minimum_level.console then
        vim.schedule(function()
          notify(msg, log_level)
        end)
      end
    end
  end

  ---@param level neotree.Logger.Config.Level
  log.set_level = function(level)
    ---@param lvl neotree.Log.Level
    ---@return vim.log.levels
    local to_loglevel = function(lvl)
      if type(lvl) == "number" then
        return lvl
      end

      if type(lvl) == "string" then
        local levelupper = lvl:upper()
        for name, level_num in pairs(Levels) do
          if levelupper == name then
            return level_num
          end
        end
      end
      notify("Couldn't resolve log level " .. lvl .. "defaulting to log level INFO", Levels.WARN)
      return Levels.INFO
    end

    if type(level) == "table" then
      log.minimum_level = {
        file = to_loglevel(level.file),
        console = to_loglevel(level.console),
      }
    else
      ---@cast level neotree.Log.Level
      log.minimum_level = {
        file = to_loglevel(level),
        console = math.max(to_loglevel(level), Levels.INFO),
      }
    end

    ---@class neotree.Logger.LevelConfig
    ---@field name string
    ---@field hl string

    log.trace = logfunc(Levels.TRACE, make_string)
    log.debug = logfunc(Levels.DEBUG, make_string)
    log.info = logfunc(Levels.INFO, make_string)
    log.warn = logfunc(Levels.WARN, make_string)
    log.error = logfunc(Levels.ERROR, make_string)
    log.fatal = logfunc(Levels.FATAL, make_string)
    -- tree-sitter queries recognize any .format and highlight it w/ string.format highlights
    log.at = {
      trace = {
        format = logfunc(Levels.TRACE, string.format),
      },
      debug = {
        format = logfunc(Levels.DEBUG, string.format),
      },
      info = {
        format = logfunc(Levels.INFO, string.format),
      },
      warn = {
        format = logfunc(Levels.WARN, string.format),
      },
      error = {
        format = logfunc(Levels.ERROR, string.format),
      },
      fatal = {
        format = logfunc(Levels.FATAL, string.format),
      },
    }
  end

  log.set_level(config.level)

  ---@param file string|boolean
  ---@param quiet boolean?
  ---@return boolean using_file
  log.use_file = function(file, quiet)
    if file == false then
      config.use_file = false
      if not quiet then
        log.info("Logging to file disabled")
      end
      return config.use_file
    end
    log.outfile = type(file) == "string" and file or initial_filepath
    local fp, err = io.open(log.outfile, "a+")

    if not fp then
      config.use_file = false
      log.warn("Could not open log file:", log.outfile, err)
      return config.use_file
    end

    local stat, stat_err = uv.fs_stat(log.outfile)
    if not stat then
      config.use_file = false
      log.warn("Could not stat log file:", log.outfile, stat_err)
      return config.use_file
    end

    if stat.ino ~= current_logfile_inode then
      -- the fp is pointing to a different file
      log.file = fp
      log.file:setvbuf("line")
      current_logfile_inode = stat.ino
    end
    config.use_file = true
    if not quiet then
      log.info("Logging to file:", log.outfile)
    end
    return config.use_file
  end

  ---Quick wrapper around assert that also supports subsequent args being the same as string.format (to reduce work done on happy paths)
  ---@see string.format
  ---@generic T
  ---@generic F
  ---@generic A
  ---@param v? T
  ---@param errmsg F?
  ---@param ... A
  ---@return T
  ---@return F
  ---@return A ...
  log.assert = function(v, errmsg, ...)
    if v then
      return v, errmsg, ...
    end
    if type(errmsg) == "string" then
      ---@cast errmsg string
      errmsg = errmsg:format(...)
    else
      errmsg = "assertion failed!"
    end
    if config.use_file then
      log_to_file("ERROR", errmsg)
    end
    return assert(v, errmsg)
  end

  ---@param context string
  log.new = function(context)
    local new_context = vim.deepcopy(config.context)
    return log_maker.new(
      vim.tbl_deep_extend(
        "force",
        config,
        { context = vim.list_extend({ new_context }, { context }) }
      )
    )
  end

  return log
end

return log_maker.new({})
