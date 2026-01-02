local M = {}
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local git_utils = require("neo-tree.git.utils")
local git_parser = require("neo-tree.git.parser")
local co = coroutine

---Returns arguments for `git ls-files` to returns a null-delimited list of paths for untracked files.
---@param worktree_root string
---@return string[]
local make_ls_untracked_args = function(worktree_root)
  return {
    "-C",
    worktree_root,
    "ls-files",
    "-z",
    "--full-name",
    "--directory",

    "--exclude-standard",
    "--others",
  }
end

---@param git_args string[]
---@return string[]
local ls_files_sync = function(worktree_root, git_args)
  local output = vim.fn.system({ "git", unpack(git_args) })
  assert(vim.v.shell_error == 0)
  local iter = utils.gsplit_plain(output, "\001")

  return git_parser.parse_ls_files_output(worktree_root, iter)
end

---@param git_args string[]
---@param context neotree.git.JobContext
---@param on_parsed fun(paths: string[])
local ls_files_job = function(git_args, context, on_parsed)
  git_utils.git_job(git_args, function(code, stdout_chunks)
    if code ~= 0 then
      log.warn("git.ls-files: ls-files error, code", code)
      return
    end
    local ls_files_string = table.concat(stdout_chunks)
    local ls_files_iter = utils.gsplit_plain(ls_files_string, "\000")

    local parsing_task = co.create(git_parser.parse_ls_files_output)
    local first_output =
      { log.assert(coroutine.resume(parsing_task, context.worktree_root, ls_files_iter, context)) }
    git_utils.parse_in_batches(parsing_task, context, first_output, on_parsed)
  end)
end

---Returns arguments for `git ls-files` to returns a null-delimited list of paths for ignored files.
---@param worktree_root string
---@return string[]
local make_ls_ignored_args = function(worktree_root)
  local args = make_ls_untracked_args(worktree_root)
  args[#args + 1] = "--ignored"
  return args
end

---@param worktree_root string
---@return string[]
M.ignored = function(worktree_root)
  return ls_files_sync(worktree_root, make_ls_ignored_args(worktree_root))
end

---@param context neotree.git.JobContext
---@param on_parsed fun(new_status: string[])
M.ignored_job = function(context, on_parsed)
  local ls_ignored_args = make_ls_ignored_args(context.worktree_root)
  ls_files_job(ls_ignored_args, context, on_parsed)
end

-- ---@param worktree_root string
-- ---@return string[]
-- M.untracked = function(worktree_root)
--   return ls_files_sync(worktree_root, make_ls_untracked_args(worktree_root))
-- end

-- ---@param context neotree.git.JobContext
-- ---@param on_parsed fun(new_status: string[])
-- M.untracked_job = function(context, on_parsed)
--   local ls_untracked_args = make_ls_untracked_args(context.worktree_root)
--   ls_files_job(ls_untracked_args, context, on_parsed)
-- end

return M
