local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local uv = vim.uv or vim.loop
local M = {}

---Runs a coroutine with the inputs
---@param parsing_coroutine thread
---@param batch_delay integer
---@param outputs unknown[] The first set of outputs from the coroutine
---@param on_coroutine_finish fun(success: boolean, ...: unknown)
M.run_coroutine_on_interval = function(parsing_coroutine, batch_delay, outputs, on_coroutine_finish)
  local function do_next_batch()
    if coroutine.status(parsing_coroutine) == "dead" then
      -- Completed
      on_coroutine_finish(unpack(outputs))
      return
    end

    outputs = { coroutine.resume(parsing_coroutine) }
    vim.defer_fn(do_next_batch, batch_delay)
  end
  do_next_batch()
end

---A fast check for whether we might be in a git repo. Likely has both false positives and negatives.
---@param path string
---@return string? worktree_root
---@return string? git_dir
M.might_be_in_git_repo = function(path)
  local git_work_tree = os.getenv("GIT_WORK_TREE")
  if git_work_tree then
    git_work_tree = utils.normalize_path(git_work_tree)
    if utils.is_subpath(git_work_tree, path, true) then
      local git_dir = os.getenv("GIT_DIR") or os.getenv("GIT_COMMON_DIR")
      return git_work_tree, git_dir
    end
  end
  local git_dir = vim.fs.find({ ".git" }, { limit = 1, upward = true, path = path })[1]
  if not git_dir then
    return nil, nil
  end
  local worktree_root = utils.split_path(git_dir)
  return worktree_root, git_dir
end

return M
