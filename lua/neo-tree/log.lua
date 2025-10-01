local Levels = vim.log.levels
local uv = vim.uv or vim.loop
-- log.lua
--
-- Inspired by rxi/log.lua
-- Modified by tjdevries and can be found at github.com/tjdevries/vlog.nvim
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.

---@alias neotree.Log.Level
---|vim.log.levels
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
    [Levels.OFF] = { name = "fatal", hl = "ErrorMsg" },
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

local log = {}

---@class (partial) neotree.Logger.PartialConfig : neotree.Logger.Config
---@param config neotree.Logger.PartialConfig|neotree.Logger.Config
---@param parent neotree.Logger?
---@return neotree.Logger
log.new = function(config, parent)
  ---@class neotree.Logger
  local logger = {}
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

  local outfile = string.format("%s/%s.log", vim.fn.stdpath("data"), config.plugin)

  ---@type file*
  local fp
  ---@param file string|boolean
  ---@param quiet boolean?
  logger.use_file = function(file, quiet)
    if file == false then
      if not quiet then
        logger.info("Logging to file disabled")
      end
      config.use_file = false
    else
      if type(file) == "string" then
        logger.outfile = file
      else
        logger.outfile = outfile
      end
      fp = assert(io.open(logger.outfile, "a+"))
      fp:setvbuf("line")
      config.use_file = true
      if not quiet then
        logger.info("Logging to file: " .. logger.outfile)
      end
    end
  end

  if config.use_file then
    logger.use_file(outfile)
  end

  local round = function(x, increment)
    increment = increment or 1
    x = x / increment
    return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
  end

  local inspect_opts = { depth = 2, newline = " " }
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
  local prefix = table.concat({ config.plugin, unpack(config.context) }, ".")
  ---@param name string
  ---@param msg string
  local log_to_file = function(name, msg)
    local info = debug.getinfo(4, "Sl")
    local lineinfo = info.short_src .. ":" .. info.currentline
    local str = string.format("[%-6s%s] %s: %s\n", name, os.date("%F-%T"), lineinfo, msg)
    if not fp:write(str) then
      vim.schedule(function()
        vim.notify_once("[neo-tree] Could not open log file: " .. logger.outfile)
      end)
    end
  end

  ---@type { file: vim.log.levels, console: vim.log.levels }
  logger.log_level = nil

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      fp:close()
    end,
  })

  ---@alias neotree.LogFunction fun(...)

  ---@return neotree.LogFunction
  ---@param log_level vim.log.levels
  ---@param message_maker fun(...):string
  local logfunc = function(log_level, message_maker)
    if log_level > logger.log_level.file and log_level > logger.log_level.console then
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
      if config.use_file and log_level >= logger.log_level.file then
        log_to_file(name_upper, msg)
      end

      -- Output to console
      if config.use_console and log_level >= logger.log_level.console then
        vim.schedule(function()
          notify(msg, log_level)
        end)
      end
    end
  end

  ---@param level neotree.Logger.Config.Level
  logger.set_level = function(level)
    ---@param lvl neotree.Log.Level
    ---@return vim.log.levels
    local to_loglevel = function(lvl)
      if type(lvl) == "string" then
        local levelupper = lvl:upper()
        for name, level_num in pairs(Levels) do
          if levelupper == name then
            return level_num
          end
        end
      elseif type(lvl) == "number" then
        return lvl
      end
      notify("Couldn't resolve log level " .. lvl .. "defaulting to log level INFO", Levels.WARN)
      return Levels.INFO
    end

    if type(level) == "table" then
      logger.log_level = {
        file = to_loglevel(level.file),
        console = to_loglevel(level.console),
      }
    else
      ---@cast level neotree.Log.Level
      logger.log_level = {
        file = to_loglevel(level),
        console = math.max(to_loglevel(level), Levels.INFO),
      }
    end

    ---@class neotree.Logger.LevelConfig
    ---@field name string
    ---@field hl string

    logger.trace = logfunc(Levels.TRACE, make_string)
    logger.debug = logfunc(Levels.TRACE, make_string)
    logger.info = logfunc(Levels.INFO, make_string)
    logger.warn = logfunc(Levels.WARN, make_string)
    logger.error = logfunc(Levels.ERROR, make_string)
    logger.fatal = logfunc(Levels.OFF, make_string)
  end

  logger.set_level(config.level)

  logger.assert = function(v, ...)
    if v then
      return v, ...
    end
    if config.use_file then
      log_to_file("ASSERTION ERROR", table.concat({ ... }, " "))
    end
    error(...)
  end

  logger.format = function(fmt, ...) end

  ---@param context string
  logger.new = function(context)
    local new_context = vim.deepcopy(config.context)
    return log.new(
      vim.tbl_deep_extend(
        "force",
        config,
        { context = vim.list_extend({ new_context }, { context }) }
      ),
      logger
    )
  end

  return logger
end

return log.new({})
