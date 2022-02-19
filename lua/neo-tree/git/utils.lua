local utils = require("neo-tree.utils")
local log = require("neo-tree.log")

local M = {}

M.get_repository_root = function(path)
  local cmd = "git rev-parse --show-toplevel"
  if utils.truthy(path) then
    cmd = "git -C " .. path .. " rev-parse --show-toplevel"
  end
  local ok, git_root = utils.execute_command(cmd)
  if not ok then
    log.trace("GIT ROOT ERROR ", git_root)
    return nil
  end
  git_root = git_root[1]

  if utils.is_windows then
    git_root = utils.windowize_path(git_root)
  end

  log.trace("GIT ROOT is ", git_root)
  return git_root
end

return M
