local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local uv = vim.uv or vim.loop
local M = {}

---@param cmd string[]
---@param on_exit fun(code: integer, stdout_chunks: string[], stderr_chunks: string[])
---@param cwd string?
M.job = function(cmd, on_exit, cwd)
  local stdout_chunks = {}
  local stderr_chunks = {}

  --- uv.spawn blocks for 2x longer than jobstart but jobstart replaces \001 with \n which isn't ideal for path
  --- correctness (since paths can technically have newlines).
  ---
  --- Switch to vim.system in v4.0
  local stdout = log.assert(uv.new_pipe(false))
  local stderr = log.assert(uv.new_pipe(false))
  local handle = uv.spawn("git", {
    args = cmd,
    hide = true,
    stdio = { nil, stdout, stderr },
    cwd = cwd,
  }, function(code, _)
    stdout:close()
    stderr:close()
    on_exit(code, stdout_chunks, stderr_chunks)
  end)
  if not handle then
    stdout:close()
    stderr:close()
    return
  end

  stdout:read_start(function(err, data)
    log.assert(not err, err)
    if type(data) == "string" then
      stdout_chunks[#stdout_chunks + 1] = data
    end
  end)
  stderr:read_start(function(err, data)
    log.assert(not err, err)
    if type(data) == "string" then
      stderr_chunks[#stderr_chunks + 1] = data
    end
  end)
end

---@param parsing_coroutine thread
---@param context neotree.git.JobContext
---@param outputs unknown[]
---@param on_parsed function
M.parse_in_batches = function(parsing_coroutine, context, outputs, on_parsed)
  local function do_next_batch()
    if coroutine.status(parsing_coroutine) == "dead" then
      -- Completed
      on_parsed(select(2, unpack(outputs)))
      return
    end

    outputs = { log.assert(coroutine.resume(parsing_coroutine)) }
    vim.defer_fn(do_next_batch, context.batch_delay)
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
