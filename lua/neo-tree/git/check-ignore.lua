local git_cmd = require("neo-tree.git.cmd")
local utils = require("neo-tree.utils")
local M = {}

---@param worktree_root string
---@param paths string[]
---@return string[]? ignored
---@return boolean? some_ignored
M.check = function(worktree_root, paths)
  local args = vim.list_extend({ "-C", worktree_root, "check-ignore" }, paths)
  local command = git_cmd.with_args(args, { literal_pathspecs = false })
  local result = vim.fn.system(command)
  -- 0: one or more is ignored
  -- 1: none is ignored
  if vim.v.shell_error > 1 then
    require("neo-tree.log").warn("git check-ignore error:", result)
    return nil
  end
  local ignored = {}
  for ignored_path in utils.gsplit_plain(result, "\001") do
    ignored[#ignored + 1] = utils.path_join(worktree_root, ignored_path)
  end
  return ignored, vim.v.shell_error == 0
end

return M
