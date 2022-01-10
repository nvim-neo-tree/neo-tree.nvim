local vim = vim
local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")
local renderer = require("neo-tree.ui.renderer")
local mapping_helper = require("neo-tree.mapping-helper")

-- If you add a new source, you need to add it to the sources table.
-- Each source should have a defaults module that contains the default values
-- for the source config, and a setup function that takes that config.
local sources = {
  "filesystem",
  "buffers",
  "git_status",
}

local M = {}

-- Adding this as a shortcut because the module path is so long.
M.fs = require("neo-tree.sources.filesystem")

local normalize_mappings = function(config)
  if config == nil then
    return false
  end
  local mappings = utils.get_value(config, "window.mappings", nil)
  if mappings then
    local fixed = mapping_helper.normalize_map(mappings)
    config.window.mappings = fixed
    return true
  else
    return false
  end
end

local ensure_config = function()
  if not M.config then
    M.setup()
  end
end

local src = function(source_name)
  if source_name == nil or source_name == "" then
    source_name = M.config.default_source
  end
  local success, source = pcall(require, "neo-tree.sources." .. source_name)
  if not success then
    error("Source " .. source_name .. " not found.")
  end
  source.name = source_name
  return source
end

M.close_all_except = function(source_name)
  local source = src(source_name)
  local target_pos = utils.get_value(M, "config." .. source.name .. ".window.position", "left")
  for _, name in ipairs(sources) do
    if name ~= source_name then
      local pos = utils.get_value(M, "config." .. name .. ".window.position", "left")
      if pos == target_pos then
        M.close(name)
      end
    end
  end
  M.close_all("float")
end

M.close = function(source_name)
  return src(source_name).close()
end

M.close_all = function(at_position)
  renderer.close_all_floating_windows()
  if type(at_position) == "string" and at_position > "" then
    for _, name in ipairs(sources) do
      local pos = utils.get_value(M, "config." .. name .. ".window.position", "left")
      if pos == at_position then
        M.close(name)
      end
    end
  else
    for _, name in ipairs(sources) do
      M.close(name)
    end
  end
end

M.float = function(source_name, toggle_if_open)
  source_name = src(source_name).name
  if toggle_if_open then
    if renderer.close_floating_window(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  M.close_all("float")
  M.close(source_name) -- in case this source is open in a sidebar
  src(source_name).float()
end

M.focus = function(source_name, close_others, toggle_if_open)
  if toggle_if_open then
    if M.close(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  if close_others == nil then
    close_others = true
  end
  local source = src(source_name)
  if close_others then
    M.close_all_except(source.name)
  end
  source.focus()
end

M.setup = function(config)
  config = config or {}

  -- setup the default values for all sources
  local source_defaults = {}
  for _, source_name in ipairs(sources) do
    local mod_root = "neo-tree.sources." .. source_name
    local source = require(mod_root .. ".defaults")
    source.components = require(mod_root .. ".components")
    source.commands = require(mod_root .. ".commands")
    source.name = source_name

    -- Make sure all the mappings are normalized so they will merge properly.
    normalize_mappings(source)
    normalize_mappings(config[source_name])

    -- if user sets renderers, completely wipe the default ones
    if utils.get_value(config, source_name .. ".renderers.directory") then
      source.renderers.directory = {}
    end
    if utils.get_value(config, source_name .. ".renderers.file") then
      source.renderers.file = {}
    end
    source_defaults[source_name] = source
  end
  local default_config = utils.table_merge(defaults, source_defaults)

  -- apply the users config
  M.config = utils.table_merge(default_config, config)

  -- setup the sources with the combined config
  for _, source_name in ipairs(sources) do
    src(source_name).setup(M.config[source_name])
  end
end

M.show = function(source_name, do_not_focus, close_others, toggle_if_open)
  if toggle_if_open then
    if M.close(source_name) then
      -- It was open, and now it's not.
      return
    end
  end
  if close_others == nil then
    close_others = true
  end
  local source = src(source_name)
  if close_others then
    M.close_all_except(source.name)
  end
  if do_not_focus then
    local current_win = vim.api.nvim_get_current_win()
    source.show(function()
      vim.api.nvim_set_current_win(current_win)
    end)
  else
    source.show()
  end
end

ensure_config()
return M
