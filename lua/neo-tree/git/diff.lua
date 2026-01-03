local git_utils = require("neo-tree.git.utils")
local git_parser = require("neo-tree.git.parser")
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local M = {}

---@param path string
---@param base string
---@return string[] args
local make_git_diff_name_status_args = function(path, base)
  return {
    "--no-optional-locks",
    "-C",
    path,
    "diff",
    base,
    "HEAD",
    "--name-status",
    "-z",
  }
end

---@param worktree_root string
---@param base string
---@param skip_bubbling boolean?
---@return neotree.git.Status?
M.diff_name_status = function(worktree_root, base, skip_bubbling)
  local args = make_git_diff_name_status_args(worktree_root, base)
  local res = vim.fn.system({ "git", unpack(args) })
  if vim.v.shell_error ~= 0 then
    log.warn("Could not diff HEAD vs", base)
    return nil
  end

  return git_parser.parse_diff_name_status_output(
    worktree_root,
    skip_bubbling,
    utils.gsplit_plain(res, "\001")
  )
end

---@param worktree_root string
---@param base string
---@param skip_bubbling boolean?
---@param context neotree.git.JobContext
---@param on_parsed fun(status: neotree.git.Status)
M.diff_name_status_job = function(worktree_root, base, skip_bubbling, context, on_parsed)
  local args = make_git_diff_name_status_args(worktree_root, base)
  git_utils.git_job(args, function(code, stdout_chunks)
    if code ~= 0 then
      log.warn("Could not async diff HEAD vs", base)
      return
    end
    local full_output = table.concat(stdout_chunks)
    local parsing_task = coroutine.create(git_parser.parse_diff_name_status_output)
    local first_output = {
      log.assert(
        coroutine.resume(
          parsing_task,
          worktree_root,
          skip_bubbling,
          utils.gsplit_plain(full_output, "\000"),
          context
        )
      ),
    }
    git_utils.parse_in_batches(parsing_task, context, first_output, on_parsed)
  end)
end

return M
