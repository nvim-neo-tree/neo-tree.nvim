local utils = require("neo-tree.utils")
local compat = require("neo-tree.utils._compat")
local M = {} -- Our module table

--- Helper function to get an environment variable or a default value.
---@param env_var_name string The name of the environment variable (e.g., "XDG_CONFIG_HOME").
---@param default_suffix string The suffix to append to the HOME directory if the env var is not set.
---@return string xdg_path
local function get_xdg_path(env_var_name, default_suffix)
  local path = vim.env[env_var_name]
  if utils.truthy(path) then
    return path
  else
    local home = vim.env.HOME
    if utils.truthy(home) then
      return utils.path_join(home, default_suffix)
    else
      return utils.path_join(vim.fn.stdpath("data"), "neo-tree.nvim", env_var_name)
    end
  end
end

--- Helper function for XDG_RUNTIME_DIR, which has a specific fallback.
---@return string? xdg_runtime_dir
local function get_xdg_runtime_dir()
  local path = vim.env.XDG_RUNTIME_DIR
  return utils.truthy(path) and path or nil
end

--- Helper function to get XDG_CONFIG_DIRS or XDG_DATA_DIRS.
---These are colon-separated lists of directories.
---@param env_var_name string The name of the environment variable (e.g., "XDG_CONFIG_DIRS").
---@param default_paths string The default colon-separated paths if the env var is not set.
---@return string[] dirpaths
local function get_xdg_dirs(env_var_name, default_paths)
  local paths_str = vim.env[env_var_name]
  paths_str = utils.truthy(paths_str) and paths_str or default_paths
  local paths = {}
  for path in utils.gsplit_plain(paths_str, ":") do
    table.insert(paths, path)
  end
  return paths
end

-- Initialize the XDG paths
function M.init()
  -- User-specific base directories
  M.config_home = get_xdg_path("XDG_CONFIG_HOME", ".config")
  M.data_home = get_xdg_path("XDG_DATA_HOME", ".local/share")
  M.state_home = get_xdg_path("XDG_STATE_HOME", ".local/state")
  M.cache_home = get_xdg_path("XDG_CACHE_HOME", ".cache")

  -- Runtime directory (special case, no HOME fallback)
  M.runtime_dir = get_xdg_runtime_dir()

  -- System-wide base directories (colon-separated lists)
  M.config_dirs = get_xdg_dirs("XDG_CONFIG_DIRS", "/etc/xdg")
  M.data_dirs = get_xdg_dirs("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
end

-- Call init to populate the module table when the module is loaded.
M.init()

return M
