local M = {}
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local git_utils = require("neo-tree.git.utils")
local git_cmd = require("neo-tree.git.cmd")
local git_parser = require("neo-tree.git.parser")
local co = coroutine

---Returns arguments for `git ls-files` to returns a null-delimited list of paths for untracked files.
---@param worktree_root string
---@return string[]
local make_ls_untracked_args = function(worktree_root)
  return git_cmd.with_args({
    "-C",
    worktree_root,
    "ls-files",
    "-z",
    "--full-name",
    "--directory",

    "--exclude-standard",
    "--others",
  })
end

---Returns arguments for `git ls-files` to returns a null-delimited list of paths for ignored files.
---@param worktree_root string
---@return string[]
local make_ls_ignored_cmd = function(worktree_root)
  local cmd = make_ls_untracked_args(worktree_root)
  cmd[#cmd + 1] = "--ignored"
  return cmd
end

---@param worktree_root string
---@return string[]
M.ignored = function(worktree_root)
  local cmd = make_ls_ignored_cmd(worktree_root)
  local output = vim.fn.system(cmd)
  assert(vim.v.shell_error == 0)
  local iter = utils.gsplit_plain(output, "\001")

  return git_parser.parse_ls_files_output(worktree_root, iter)
end

---@param context neotree.git.JobContext
---@param on_parsed fun(new_status: string[]?, err: string?)
M.ignored_job = function(context, on_parsed)
  local ls_ignored_cmd = make_ls_ignored_cmd(context.worktree_root)
  utils.job(ls_ignored_cmd, nil, function(code, stdout_chunks)
    if code ~= 0 then
      on_parsed(nil, "git.ls-files: ls-files error, code " .. code)
      return
    end
    local ls_files_string = table.concat(stdout_chunks)
    local ls_files_iter = utils.gsplit_plain(ls_files_string, "\000")

    local parsing_task = co.create(git_parser.parse_ls_files_output)
    local first_output =
      { coroutine.resume(parsing_task, context.worktree_root, ls_files_iter, context) }
    git_utils.run_coroutine_on_interval(
      parsing_task,
      context.batch_delay,
      first_output,
      function(success, paths)
        if success then
          on_parsed(paths)
        else
          local err = paths
          on_parsed(nil, err)
        end
      end
    )
  end)
end

return M
