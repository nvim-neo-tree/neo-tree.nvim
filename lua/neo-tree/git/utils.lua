local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local uv = vim.uv or vim.loop
local M = {}

---@param git_args string[]
---@param on_exit fun(code: integer, stdout_chunks: string[], stderr_chunks: string[])
---@param cwd string?
M.git_job = function(git_args, on_exit, cwd)
  local stdout_chunks = {}
  local stderr_chunks = {}

  --- uv.spawn blocks for 2x longer than jobstart but jobstart replaces \001 with \n which isn't ideal for path
  --- correctness (since paths can technically have newlines).
  ---
  --- Switch to vim.system in v4.0
  local stdout = log.assert(uv.new_pipe())
  local stderr = log.assert(uv.new_pipe())
  uv.spawn("git", {
    args = git_args,
    hide = true,
    stdio = { nil, stdout, stderr },
    cwd = cwd,
  }, function(code, _)
    stdout:close()
    stdout:shutdown()
    stderr:close()
    stdout:shutdown()
    on_exit(code, stdout_chunks, stderr_chunks)
  end)

  stdout:read_start(function(err, data)
    log.assert(not err, err)
    if type(data) == "string" then
      stdout_chunks[#stdout_chunks + 1] = data
    end
  end)
  stdout:read_start(function(err, data)
    log.assert(not err, err)
    if type(data) == "string" then
      stdout_chunks[#stdout_chunks + 1] = data
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
---@return boolean
M.might_be_in_git_repo = function(path)
  local git_dir_from_env = os.getenv("GIT_DIR") or os.getenv("GIT_COMMON_DIR")
  if git_dir_from_env then
    local stat = uv.fs_stat(utils.normalize_path(git_dir_from_env))
    return not not stat
  end
  local git_work_tree = os.getenv("GIT_WORK_TREE")
  if git_work_tree then
    git_work_tree = utils.normalize_path(git_work_tree)
    if utils.is_subpath(git_work_tree, path) then
      return true
    end
  end
  return #vim.fs.find({ ".git" }, { limit = 1, upward = true, path = path }) > 0
end

return M
