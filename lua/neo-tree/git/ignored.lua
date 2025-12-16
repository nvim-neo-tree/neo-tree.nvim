local M = {}
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local git_utils = require("neo-tree.git.utils")
local co = coroutine

---@param path string
---@return string path_with_no_trailing_slash
local trim_trailing_slash = function(path)
  return path:sub(-1, -1) == "/" and path:sub(1, -2) or path
end

---@param worktree_root string The git status table to override, if any.
---@param filepaths_iter fun():string? An iterator that returns each line of the status.
---@param git_status neotree.git.Status? The git status table to override, if any.
---@param batch_size integer? This will set how many to parse before yielding or returning.
---@return table<string, string>
local parse_ls_files_ignored_output = function(
  worktree_root,
  filepaths_iter,
  git_status,
  batch_size
)
  local worktree_root_dir = worktree_root
  if not vim.endswith(worktree_root_dir, utils.path_separator) then
    worktree_root_dir = worktree_root_dir .. utils.path_separator
  end

  if batch_size then
    assert(coroutine.running(), "batch_size shouldn't be provided if not in non-main coroutine")
  end
  local num_in_batch = 0

  local ignored_status = git_status or {}
  for relpath in filepaths_iter do
    relpath = trim_trailing_slash(relpath)
    if utils.is_windows then
      relpath = utils.windowize_path(relpath)
    end

    local abspath = worktree_root_dir .. relpath
    ignored_status[abspath] = "!"
    if batch_size then
      num_in_batch = num_in_batch + 1
      if num_in_batch >= batch_size then
        num_in_batch = 0
        if coroutine.running() then
          coroutine.yield(git_status)
        else
          break
        end
      end
    end
  end
  return ignored_status
end

---Returns arguments for `git ls-files` that returns a null-delimited list of relative paths of ignored files.
---@param worktree_root string
---@return string[]
local make_ls_files_ignored_args = function(worktree_root)
  return {
    "-C",
    worktree_root,
    "ls-files",
    "--exclude-standard",
    "--others",
    "--directory",
    "--ignored",
    "--full-name",
    "-z",
  }
end

---@param worktree_root string
---@return table<string, string>
M.ignored_status = function(worktree_root)
  local ignore_output = vim.fn.system({ "git", unpack(make_ls_files_ignored_args(worktree_root)) })
  assert(vim.v.shell_error == 0)
  local iter = utils.gsplit_plain(ignore_output, "\001")

  return parse_ls_files_ignored_output(worktree_root, iter)
end

---@param context neotree.git.JobContext
---@param on_parsed fun(new_status: table<string, string>)
M.add_ignored_status_job = function(context, on_parsed)
  local ignored_list_args = make_ls_files_ignored_args(context.worktree_root)

  git_utils.git_job(ignored_list_args, function(code, stdout_chunks)
    if code ~= 0 then
      log.warn("git.status_async: could not ls-files to get ignored files")
      return
    end
    local ls_files_string = table.concat(stdout_chunks)
    local ignored_list_iter = utils.gsplit_plain(ls_files_string, "\000")

    local parsing_task = co.create(parse_ls_files_ignored_output)
    log.assert(
      co.resume(
        parsing_task,
        context.worktree_root,
        ignored_list_iter,
        context.git_status,
        context.batch_size
      )
    )
    local processed_lines = 0
    local function do_next_batch_later()
      if co.status(parsing_task) == "dead" then
        -- Completed
        on_parsed(context.git_status)
        return
      end

      processed_lines = processed_lines + context.batch_size
      if processed_lines > context.max_lines then
        -- Reached max line count
        on_parsed(context.git_status)
        return
      end

      log.assert(co.resume(parsing_task))
      vim.defer_fn(do_next_batch_later, context.batch_delay)
    end
    do_next_batch_later()
  end)
end

return M
