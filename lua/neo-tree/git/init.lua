local utils = require("neo-tree.utils")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local parser = require("neo-tree.git.parser")
local uv = vim.uv or vim.loop
local co = coroutine
---@type metatable
local weak_kv = { __mode = "kv" }

local M = {}

---@type table<string, neotree.git.Status>
M.statuses = setmetatable({}, weak_kv)
---@type table<boolean, table<string, string>>
M._raw_status_text_cache = setmetatable({}, weak_kv)

local gsplit_plain = vim.fn.has("nvim-0.9") == 1 and { plain = true } or true
local git_available = vim.fn.executable("git") == 1

---@return 1|2? highest_supported_porcelain_version_if_git
local get_git_porcelain_version = function()
  if not git_available then
    return nil
  end
  local git_version_success, git_version_output = utils.execute_command({ "git", "--version" })
  if not git_version_success then
    log.warn("`git --version` failed")
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  local version_output = vim.split(git_version_output[1], ".", gsplit_plain)
  local git_version = {
    major = tonumber(version_output[1]:sub(#"git version " + 1)),
    minor = tonumber(version_output[2]),
    patch = tonumber(version_output[3] or 0),
  }

  local has_porcelain_v2 = git_version and git_version.major >= 2 and git_version.minor >= 12
  return has_porcelain_v2 and 2 or 1
end

---@type 1|2?
M._supported_porcelain_version = nil

---@alias neotree.git.Status table<string, string>

---@param git_root string
---@param git_status neotree.git.Status?
---@param ignored string[]?
local change_git_status = function(git_root, git_status, ignored)
  local last_git_status = M.statuses[git_root]
  if type(last_git_status) ~= type(git_status) then
    -- updating or deleting an existing root dir
    M._root_dir_cache = setmetatable({}, weak_kv)
  end
  M.statuses[git_root] = git_status
  vim.schedule(function()
    ---@class neotree.event.args.GIT_STATUS_CHANGED
    local args = {
      git_root = git_root,
      git_status = git_status,
      git_ignored = ignored,
    }
    events.fire_event(events.GIT_STATUS_CHANGED, args)
  end)
end

local porcelain_flag = {
  "--porcelain=v1",
  "--porcelain=v2",
}
---@param worktree_root string
---@param porcelain_version 1|2
---@param untracked_files "all"|"no"|"normal"?
---@param ignored "traditional"|"no"|"matching"?
---@param paths string[]?
---@return string[] args
local make_git_status_args = function(
  porcelain_version,
  worktree_root,
  untracked_files,
  ignored,
  paths
)
  ignored = ignored or "traditional"
  local args = {
    "--no-optional-locks",
    "-C",
    worktree_root,
    "status",
    porcelain_flag[porcelain_version],
    "-z",
    "--ignored=" .. ignored,
  }
  if untracked_files then
    args[#args + 1] = "--untracked-files=" .. untracked_files
  end
  events.fire_event(events.BEFORE_GIT_STATUS, {
    status_args = args,
    git_root = worktree_root,
  })
  if paths then
    args[#args + 1] = "--"
    for _, path in ipairs(paths) do
      args[#args + 1] = path
    end
  end
  return args
end

---Parse "git status" output for the current working directory.
---@param base string? git ref base
---@param skip_bubbling boolean? Whether to skip bubling up status to directories
---@param path string? Path to run the git status command in, defaults to cwd.
---@return neotree.git.Status? git_status the neotree.Git.Status of the given root, if there's a valid git status there
---@return string? git_root
M.status = function(base, skip_bubbling, path)
  local worktree_root = M.get_worktree_info(path)
  if not utils.truthy(worktree_root) then
    return nil
  end
  ---@cast worktree_root -nil

  M._supported_porcelain_version = M._supported_porcelain_version or get_git_porcelain_version()
  if not M._supported_porcelain_version then
    log.debug("Can't run git status")
    return
  end
  local status_cmd = {
    "git",
    unpack(make_git_status_args(M._supported_porcelain_version, worktree_root)),
  }

  local raw_status_text = vim.fn.system(status_cmd)
  assert(vim.v.shell_error == 0)
  local status_text = raw_status_text:gsub("\001", "\000")

  local last_status_text = M._raw_status_text_cache[worktree_root]
  if status_text == last_status_text then
    -- return the current status
    return M.statuses[worktree_root], worktree_root
  end
  M._raw_status_text_cache[worktree_root] = status_text

  skip_bubbling = not not skip_bubbling
  ---@diagnostic disable-next-line: param-type-mismatch
  local status_iter = vim.gsplit(status_text, "\000", gsplit_plain)
  local git_status = parser._parse_porcelain(
    M._supported_porcelain_version,
    worktree_root,
    status_iter,
    nil,
    nil,
    skip_bubbling
  )

  change_git_status(worktree_root, git_status)
  return git_status, worktree_root
end

---@param git_args string[]
---@param on_exit fun(code: integer, stdout_chunks: string[], stderr_chunks: string[])
local git_job = function(git_args, on_exit)
  local stdout_chunks = {}
  local stderr_chunks = {}

  --- uv.spawn blocks for 2x longer than jobstart but jobstart replaces \001 with \n which isn't ideal for path
  --- correctness (since paths can technically have newlines).
  ---
  --- Switch to vim.system in v4.0
  local stdout = log.assert(uv.new_pipe(true))
  local stderr = log.assert(uv.new_pipe(true))
  uv.spawn("git", {
    args = git_args,
    hide = true,
    stdio = { nil, stdout, stderr },
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

---Creates a job (vim job) for `git status`
---@param context neotree.git.JobContext
---@param git_args string[]? nil to use default of make_git_status_args, which includes all files
---@param on_changed_status fun(gs: neotree.git.Status, ignored: string[])
local git_status_job = function(context, git_args, on_changed_status, skip_bubbling)
  local args = git_args or make_git_status_args(M._supported_porcelain_version, context.git_root)
  git_job(args, function(code, stdout_chunks, stderr_chunks)
    if code ~= 0 then
      log.at.warn.format(
        "git status async process exited abnormally, code: %s, %s, %s",
        code,
        table.concat(stdout_chunks),
        table.concat(stderr_chunks)
      )
      return
    end

    local status_text = table.concat(stdout_chunks)
    local past_raw_status_text = M._raw_status_text_cache[context.git_root]
    if status_text == past_raw_status_text then
      -- stdout text did not change.
      return
    end
    M._raw_status_text_cache[context.git_root] = status_text

    ---@diagnostic disable-next-line: param-type-mismatch
    local status_iter = vim.gsplit(status_text, "\000", gsplit_plain)
    local parsing_task = co.create(parser._parse_porcelain)
    local _, _, ignored = log.assert(
      co.resume(
        parsing_task,
        M._supported_porcelain_version,
        context.git_root,
        status_iter,
        context.git_status,
        context.batch_size,
        skip_bubbling
      )
    )
    local processed_lines = 0
    local function do_next_batch_later()
      if co.status(parsing_task) == "dead" then
        -- Completed
        on_changed_status(context.git_status, ignored)
        return
      end

      if processed_lines > context.max_lines then
        -- Reached max line count
        on_changed_status(context.git_status, ignored)
        return
      end

      log.assert(co.resume(parsing_task))
      processed_lines = processed_lines + context.batch_size
      vim.defer_fn(do_next_batch_later, context.batch_delay)
    end
    do_next_batch_later()
  end)
  ---@diagnostic disable-next-line: missing-fields
end

---Runs `git status` asynchronously, will update neo-tree once finished.
---@param path string path to run commands in
---@param base string git ref base
---@param opts neotree.Config.GitStatusAsync
M.status_async = function(path, base, opts)
  M.get_worktree_info(path, function(worktree_root)
    if not worktree_root then
      log.trace("status_async: not a git folder:", path)
      return
    end

    log.trace("git.status_async called")

    local event_id = "git_status_" .. worktree_root

    utils.debounce(event_id, function()
      vim.schedule(function()
        M._supported_porcelain_version = M._supported_porcelain_version
          or get_git_porcelain_version()
        ---@class neotree.git.JobContext
        local ctx = {
          git_root = worktree_root,
          git_status = {},
          batch_size = opts.batch_size or 1000,
          batch_delay = opts.batch_delay or 10,
          max_lines = opts.max_lines or 100000,
        }
        if not M.statuses[ctx.git_root] then
          -- do a fast scan first to get basic things in, then a full scan with (potentially) untracked files
          local fast_args = make_git_status_args(
            M._supported_porcelain_version,
            worktree_root,
            "no",
            "traditional",
            { path }
          )
          git_status_job(ctx, fast_args, function(fast_status, ignored)
            change_git_status(worktree_root, fast_status, ignored)
            git_job(
              { "-C", worktree_root, "config", "--get", "status.showUntrackedFiles" },
              function(code, stdout_chunks, _)
                -- https://git-scm.com/docs/git-config
                -- This command will fail with non-zero status upon error. Some exit codes are:
                -- The section or key is invalid (ret=1),
                -- no section or name was provided (ret=2),
                -- the config file is invalid (ret=3),
                -- the config file cannot be written (ret=4),
                -- you try to unset an option which does not exist (ret=5),
                -- you try to unset/set an option for which multiple lines match (ret=5), or
                -- you try to use an invalid regexp (ret=6).
                if code < 0 or 1 < code then
                  log.warn("git.status_async: status.showUntrackedFiles check failed, code", code)
                  return
                end
                local untracked_setting = table.concat(stdout_chunks)
                if untracked_setting:find("no", 1, true) then
                  log.debug(
                    "git.status_async: status.showUntrackedFiles == 'no', skipping full check"
                  )
                  return
                end
                git_status_job(ctx, nil, function(full_status, full_ignored)
                  change_git_status(worktree_root, full_status, full_ignored)
                end, true)
              end
            )
          end)
        else
          git_status_job(ctx, nil, function(full_status, ignored)
            change_git_status(worktree_root, full_status, ignored)
          end)
        end
      end)
    end, 1000, utils.debounce_strategy.CALL_FIRST_AND_LAST, utils.debounce_action.START_ASYNC_JOB)
  end)
end

---A fast check for whether we might be in a git repo. Likely has both false positives and negatives.
local might_be_in_git_repo = function()
  local git_dir_from_env = vim.env.GIT_DIR or vim.env.GIT_COMMON_DIR
  if git_dir_from_env then
    local stat = uv.fs_stat(utils.normalize_path(git_dir_from_env))
    if stat then
      return stat
    end
  end
  return vim.fs.find(".git", { limit = 1, upward = true })
end

---@param state neotree.State
---@param items neotree.FileItem[]
M.mark_gitignored = function(state, items)
  -- upward and downward are relative to state.path
  local upward_statuses = {}
  local downward_statuses = {}
  for worktree_root, git_status in pairs(M.statuses) do
    if utils.is_subpath(worktree_root, state.path, true) then
      upward_statuses[#upward_statuses + 1] = git_status
    elseif utils.is_subpath(state.path, worktree_root, true) then
      downward_statuses[#downward_statuses + 1] = git_status
    end
  end
  if #upward_statuses == 0 and might_be_in_git_repo() then
    upward_statuses[#upward_statuses + 1] = M.status(nil, false, state.path)
  end
  for _, i in ipairs(items) do
    for _, git_status in ipairs({ unpack(upward_statuses), unpack(downward_statuses) }) do
      local status = git_status[i.path]
      if status then
        if status == "!" then
          i.filtered_by = i.filtered_by or {}
          i.filtered_by.gitignored = true
        end
        break
      end
    end
  end
end

---Invalidate cache for path and parents, updating trees as needed
---@param path string
local invalidate_cache = function(path)
  ---@type string?
  local parent = utils.split_path(path)

  while parent do
    local cache_entry = M.statuses[parent]
    if cache_entry ~= nil then
      change_git_status(parent, nil)
    end
    parent = utils.split_path(parent)
  end
end

---@param ok boolean
---@param path string
---@param stdout_lines string[]
---@param stderr_lines string[]?
---@return string[] normalized_stdout_paths
local process_output = function(ok, path, stdout_lines, stderr_lines)
  if not ok then
    log.trace("GIT ROOT ERROR", stderr_lines or {})
    invalidate_cache(path)
    return {}
  end

  local lines = stdout_lines
  for i, p in ipairs(stdout_lines) do
    if #p == 0 then
      break
    elseif utils.is_windows then
      lines[i] = utils.windowize_path(p)
    end
  end
  return lines
end

---Finds the worktree root, git root, and superproject worktree root by running 3 separate commands. Only necessary in
---the edge case that a path contains a newline.
---@param path string
---@param callback fun(worktree_root: string?, git_dir: string?, superproject_worktree_root: string?)? Async if provided.
---@return string? worktree_root
---@return string? git_dir
---@return string? superproject_worktree_root
local get_worktree_info_slow = function(path, callback)
  local base_args = {
    "-C",
    path,
    "rev-parse",
  }
  ---@type string[][]
  local argument_lists = {}
  for _, arg in ipairs({
    "--show-toplevel",
    "--absolute-git-dir",
    "--show-superproject_worktree_root",
  }) do
    local args = { unpack(base_args) }
    args[#args + 1] = arg
    argument_lists[#argument_lists + 1] = args
  end

  local worktree_root = vim.fn.system({ "git", unpack(argument_lists[1]) })
  if vim.v.shell_error ~= 0 then
    return
  end
  local git_dir = vim.fn.system({ "git", unpack(argument_lists[2]) })
  if vim.v.shell_error ~= 0 then
    return
  end
  local superproject_worktree_root = vim.fn.system({ "git", unpack(argument_lists[3]) })
  if vim.v.shell_error ~= 0 then
    return
  end
  local paths = { worktree_root, git_dir, superproject_worktree_root }
  for i, p in ipairs(paths) do
    if #p == 0 then
      paths[i] = nil
    elseif utils.is_windows then
      paths[i] = utils.windowize_path(p)
    end
  end
  if type(callback) == "function" then
    vim.schedule(function()
      callback(paths[1], paths[2], paths[3])
    end)
    return
  end
  return paths[1], paths[2], paths[3]
end

---Finds the worktree root and the corresponding git directory, already normalized.
---@param path string? Defaults to cwd.
---@param callback fun(worktree_root: string?, git_dir: string?, superproject_worktree_root: string?)? Async if provided.
---@return string? worktree_root
---@return string? git_dir
---@return string? superproject_worktree_root
M.get_worktree_info = function(path, callback)
  path = path or log.assert(uv.cwd())

  if path:find("\n", 1, true) then
    return get_worktree_info_slow(path, callback)
  end

  local rev_parse_args = {
    "-C",
    path,
    "rev-parse",
    "--show-toplevel",
    "--absolute-git-dir",
    "--show-superproject-working-tree",
  }

  if callback then
    assert(type(callback) == "function", "callback for git status should be a function")
    ---@diagnostic disable-next-line: missing-fields
    git_job(rev_parse_args, function(code, stdout_chunks, stderr_chunks)
      local full_stdout = table.concat(stdout_chunks, "")
      ---@diagnostic disable-next-line: param-type-mismatch
      local stdout_lines = vim.split(full_stdout, "\n", gsplit_plain)
      local info = process_output(code == 0, path, stdout_lines, stderr_chunks)
      local worktree_root, git_dir, superproject_worktree_root = unpack(info)
      callback(worktree_root, git_dir, superproject_worktree_root)
    end)
    return
  end

  M._supported_porcelain_version = M._supported_porcelain_version or get_git_porcelain_version()
  local ok, rev_parse_lines = utils.execute_command({ "git", unpack(rev_parse_args) })
  local info = process_output(ok, path, rev_parse_lines, rev_parse_lines)
  local worktree_root, git_dir, superproject_worktree_root = unpack(info)
  return worktree_root, git_dir, superproject_worktree_root
end

---@type table<string, string|false>
M._root_dir_cache = setmetatable({}, weak_kv)

---Given a normalized path, find whether a git status exists for it.
---@param path string A normalized path.
---@return string|false? worktree_root
---@return neotree.git.Status? status
M.find_existing_status = function(path)
  local cached = M._root_dir_cache[path]
  if cached ~= nil then
    return cached, cached and M.statuses[cached]
  end
  for root_dir, status in pairs(M.statuses) do
    if utils.is_subpath(root_dir, path, true) then
      M._root_dir_cache[path] = root_dir
      return root_dir, status
    end
  end
  M._root_dir_cache[path] = false
end

return M
