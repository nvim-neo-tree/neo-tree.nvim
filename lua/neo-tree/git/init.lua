local utils = require("neo-tree.utils")
local git_utils = require("neo-tree.git.utils")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local parser = require("neo-tree.git.status_parser")
local uv = vim.uv or vim.loop
local co = coroutine
---@type metatable
local weak_kv = { __mode = "kv" }

local M = {}

---@type table<string, neotree.git.Status>
M.statuses = setmetatable({}, weak_kv)

---@type table<string, string>
M._raw_status_text_cache = setmetatable({}, { __mode = "k" })

---@alias (private) neotree.git._StatusPorcelainVersion
---|1
---|2
---|false
---|nil

---@type neotree.git._StatusPorcelainVersion
M._supported_status_porcelain_version = nil

---@return neotree.git._StatusPorcelainVersion highest_supported_porcelain_version_if_git
local find_status_porcelain_version = function()
  if not vim.fn.executable("git") == 1 then
    log.debug("`git` not available")
    return false
  end
  local git_version_success, git_version_output = utils.execute_command({ "git", "--version" })
  if not git_version_success then
    log.warn("`git --version` failed")
    return false
  end
  local version_output = utils.gsplit_plain(table.concat(git_version_output), ".")
  local major_str = version_output()
  local minor_str = version_output()
  local major = major_str and tonumber(major_str:sub(#"git version " + 1))
  local minor = tonumber(minor_str)

  local has_porcelain_v2 = major and major >= 2 and minor >= 12
  return has_porcelain_v2 and 2 or 1
end

---@return neotree.git._StatusPorcelainVersion highest_supported_porcelain_version_if_git
local get_status_porcelain_version = function()
  if M._supported_status_porcelain_version then
    return M._supported_status_porcelain_version
  end

  M._supported_status_porcelain_version = find_status_porcelain_version()
  return M._supported_status_porcelain_version
end

---@alias neotree.git.Status table<string, string>

---@param worktree_root string
---@param git_status neotree.git.Status?
local change_git_status = function(worktree_root, git_status, opts)
  local last_git_status = M.statuses[worktree_root]
  if type(last_git_status) ~= type(git_status) then
    -- updating or deleting an existing root dir
    M._root_dir_cache = setmetatable({}, weak_kv)
  end
  M.statuses[worktree_root] = git_status
  vim.schedule(function()
    ---@class neotree.event.args.GIT_STATUS_CHANGED
    local args = {
      git_root = worktree_root,
      git_status = git_status,
    }
    events.fire_event(events.GIT_STATUS_CHANGED, args)
  end)
end

local porcelain_flag = {
  "--porcelain=v1",
  "--porcelain=v2",
}

---@class (private) neotree.git._StatusCommandArgs
---@field untracked_files "all"|"no"|"normal"?
---@field ignored "traditional"|"no"|"matching"?
---@field paths string[]?

---@param worktree_root string
---@param porcelain_version 1|2
---@param opts neotree.git._StatusCommandArgs?
---@return string[] args
local make_git_status_args = function(porcelain_version, worktree_root, opts)
  opts = opts or {}
  opts.ignored = opts.ignored or "traditional"
  local args = {
    "--no-optional-locks",
    "-C",
    worktree_root,
    "status",
    porcelain_flag[porcelain_version],
    "-z",
    "--ignored=" .. opts.ignored,
  }
  if opts.untracked_files then
    args[#args + 1] = "--untracked-files=" .. opts.untracked_files
  end
  events.fire_event(events.BEFORE_GIT_STATUS, {
    status_args = args,
    git_root = worktree_root,
  })
  if opts.paths then
    args[#args + 1] = "--"
    for _, path in ipairs(opts.paths) do
      args[#args + 1] = path
    end
  end
  return args
end

---Get "git status" output for the given path
---@param base string? git ref base
---@param skip_bubbling boolean? Whether to skip bubling up status to directories
---@param path string Path to run the git status command in, defaults to cwd.
---@return neotree.git.Status? git_status the neotree.Git.Status of the given root, if there's a valid git status there
---@return string? worktree_root
M.status = function(base, skip_bubbling, path)
  local worktree_root = M.find_worktree_info(path)
  if not utils.truthy(worktree_root) then
    return nil, nil
  end

  ---@cast worktree_root -nil
  local status_porcelain_version = get_status_porcelain_version()
  if not status_porcelain_version then
    return nil, nil
  end
  local status_cmd = {
    "git",
    unpack(make_git_status_args(status_porcelain_version, worktree_root)),
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
  local status_iter = utils.gsplit_plain(status_text, "\000")
  local git_status = parser._parse_status_porcelain(
    status_porcelain_version,
    worktree_root,
    status_iter,
    nil,
    nil,
    skip_bubbling
  )

  change_git_status(worktree_root, git_status)
  return git_status, worktree_root
end

---Creates a job (vim job) for `git status`
---@param context neotree.git.JobContext
---@param git_args string[]? nil to use default of make_git_status_args, which includes all files
---@param on_parsed fun(gs: neotree.git.Status)
local git_status_job = function(context, git_args, on_parsed, skip_bubbling)
  local args = git_args or make_git_status_args(context.porcelain_version, context.worktree_root)
  git_utils.git_job(args, function(code, stdout_chunks, stderr_chunks)
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
    local past_raw_status_text = M._raw_status_text_cache[context.worktree_root]
    if status_text == past_raw_status_text then
      -- stdout text did not change.
      return
    end
    M._raw_status_text_cache[context.worktree_root] = status_text

    local status_iter = utils.gsplit_plain(status_text, "\000")
    local parsing_task = co.create(parser._parse_status_porcelain)
    log.assert(
      co.resume(
        parsing_task,
        get_status_porcelain_version(),
        context.worktree_root,
        status_iter,
        context.git_status,
        context.batch_size,
        skip_bubbling
      )
    )
    local processed_lines = context.batch_size
    local function do_next_batch_later()
      if co.status(parsing_task) == "dead" then
        -- Completed
        on_parsed(context.git_status)
        return
      end

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

---Runs `git status` asynchronously, will update neo-tree once finished.
---@param path string path to run commands in
---@param base string git ref base
---@param opts neotree.Config.GitStatusAsync
M.status_async = function(path, base, opts)
  M.find_worktree_info(path, function(worktree_root)
    if not worktree_root then
      log.trace("status_async: not a git folder:", path)
      return
    end

    log.trace("git.status_async called")

    local event_id = "git_status_" .. worktree_root

    utils.debounce(event_id, function()
      vim.schedule(function()
        local git_status_porcelain_version = get_status_porcelain_version()
        if not git_status_porcelain_version then
          return
        end
        ---@class neotree.git.JobContext
        local ctx = {
          porcelain_version = git_status_porcelain_version,
          worktree_root = worktree_root,
          git_status = {},
          num_in_batch = 0,
          batch_size = opts.batch_size or 1000,
          batch_delay = opts.batch_delay or 10,
          max_lines = opts.max_lines or 100000,
        }
        if not M.statuses[ctx.worktree_root] then
          -- do a fast scan first to get basic things in
          local fast_args = make_git_status_args(git_status_porcelain_version, worktree_root, {
            untracked_files = "no",
          })
          git_status_job(ctx, fast_args, function(fast_status)
            change_git_status(worktree_root, fast_status)
            -- Get ignored statuses
            require("neo-tree.git.ignored").add_ignored_status_job(ctx, function(new_status)
              change_git_status(worktree_root, new_status)
            end)
            -- Get the full status
            git_utils.git_job(
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

                git_status_job(ctx, nil, function(full_status)
                  change_git_status(worktree_root, full_status)
                end, true)
              end
            )
          end)
        else
          git_status_job(ctx, nil, function(full_status)
            change_git_status(worktree_root, full_status)
          end)
        end
      end)
    end, 1000, utils.debounce_strategy.CALL_FIRST_AND_LAST, utils.debounce_action.START_ASYNC_JOB)
  end)
end

do
  ---A fast check for whether we might be in a git repo. Likely has both false positives and negatives.
  ---@param path string
  ---@return boolean
  local might_be_in_git_repo = function(path)
    local git_dir_from_env = vim.env.GIT_DIR or vim.env.GIT_COMMON_DIR
    if git_dir_from_env then
      local stat = uv.fs_stat(utils.normalize_path(git_dir_from_env))
      return not not stat
    end
    return #vim.fs.find(".git", { limit = 1, upward = true, path = path }) > 0
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

    if #upward_statuses == 0 and might_be_in_git_repo(state.path) then
      local worktree_root = M.find_worktree_info(state.path)
      if not worktree_root then
        return
      end
      local status_porcelain_version = get_status_porcelain_version()
      if not status_porcelain_version then
        return
      end
      upward_statuses[#upward_statuses + 1] =
        require("neo-tree.git.ignored").ignored_status(worktree_root)
    end

    for _, i in ipairs(items) do
      local git_statuses = { unpack(upward_statuses), unpack(downward_statuses) }
      for _, git_status in ipairs(git_statuses) do
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
M.find_worktree_info = function(path, callback)
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
    git_utils.git_job(rev_parse_args, function(code, stdout_chunks, stderr_chunks)
      local full_stdout = table.concat(stdout_chunks, "")
      local stdout_lines = {}
      for line in utils.gsplit_plain(full_stdout, "\n") do
        stdout_lines[#stdout_lines + 1] = line
      end
      local info = process_output(code == 0, path, stdout_lines, stderr_chunks)
      local worktree_root, git_dir, superproject_worktree_root = unpack(info)
      callback(worktree_root, git_dir, superproject_worktree_root)
    end)
    return
  end

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
