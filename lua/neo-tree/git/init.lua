local utils = require("neo-tree.utils")
local git_utils = require("neo-tree.git.utils")
local git_ls_files = require("neo-tree.git.ls-files")
local git_diff = require("neo-tree.git.diff")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local parser = require("neo-tree.git.parser")
local uv = vim.uv or vim.loop
local co = coroutine

---@type metatable
local weak_kv = { __mode = "kv" }

---@type metatable
local weak_k = { __mode = "kv" }

local M = {}

---@alias neotree.git.StatusCode string|[string]

---@alias neotree.git.Status table<string, neotree.git.StatusCode?>

---@alias neotree.git.BaseLookup table<string, string?>

---@class neotree.git.WorktreeInfo
---@field git_dir string
---@field status_diff table<string, neotree.git.Status?>
---@field watcher neotree.sources.filesystem.Watcher?
---@field superproject_worktree_root string?
---@field status neotree.git.Status?

---@type table<string, neotree.git.WorktreeInfo?>
M.worktrees = {}

---@param worktree_root string
---@param git_dir string
---@param superproject_worktree_root string?
---@return boolean registered_new_worktree
local try_register_worktree = function(worktree_root, git_dir, superproject_worktree_root)
  if not worktree_root then
    return false
  end

  local new_worktree = false
  ---@type neotree.git.WorktreeInfo
  local worktree = M.worktrees[worktree_root]

  if not worktree then
    new_worktree = true
    -- new root dir, invalidate root dir lookups
    M._upward_worktree_cache = setmetatable({}, weak_kv)

    worktree = {
      git_dir = log.assert(git_dir, "Git dir should exist before registering"),
      superproject_worktree_root = superproject_worktree_root,
      status_diff = {},
    }
    M.worktrees[worktree_root] = worktree
  end

  local config = require("neo-tree").config
  if config.filesystem.use_libuv_file_watcher then
    -- Fix issue(https://github.com/nvim-neo-tree/neo-tree.nvim/issues/724)
    -- After each render, there will do watcher.references - 1. When watcher.references == 0,
    -- the watcher will stop. Therefore, every time a git status refresh is triggered,
    -- watch_folder need to be triggered to do watcher.references + 1.
    worktree.watcher = require("neo-tree.git.watch").watch(worktree_root, git_dir)
  end

  return new_worktree
end

---@param worktree_root string
local delete_worktree = function(worktree_root)
  local existing_worktree = log.assert(
    M.worktrees[worktree_root],
    "Could not find worktree to delete for " .. worktree_root
  )
  M.worktrees[existing_worktree] = nil
  -- deleting worktree, invalidate root dir lookups
  M._upward_worktree_cache = setmetatable({}, weak_kv)
  vim.schedule(function()
    ---@class neotree.event.args.GIT_STATUS_CHANGED
    local args = {
      git_root = worktree_root,
    }
    events.fire_event(events.GIT_STATUS_CHANGED, args)
  end)
end

---Invalidate cache for path and parents, updating trees as needed
---@param path string
local invalidate_upward_worktrees = function(path)
  ---@type string?
  local parent = path

  while parent do
    local worktree = M.worktrees[parent]
    if worktree ~= nil then
      delete_worktree(parent)
    end
    parent = utils.split_path(parent)
  end
end

---@type table<string, string>
local raw_status_text_cache = setmetatable({}, weak_k)

---@alias (private) neotree.git._StatusPorcelainVersion
---|1
---|2
---|false

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
  if M._supported_status_porcelain_version ~= nil then
    return M._supported_status_porcelain_version
  end

  M._supported_status_porcelain_version = find_status_porcelain_version()
  return M._supported_status_porcelain_version
end

---@param worktree_root string
---@param git_status neotree.git.Status
---@param base string?
---@param git_status_diff_base neotree.git.Status?
local change_worktree_git_status = function(worktree_root, git_status, base, git_status_diff_base)
  local worktree =
    assert(M.worktrees[worktree_root], "Could not find worktree for " .. worktree_root)
  worktree.status = git_status
  if base then
    worktree.status_diff[base] = git_status_diff_base
  end
  vim.schedule(function()
    ---@class neotree.event.args.GIT_STATUS_CHANGED
    local args = {
      git_root = worktree_root,
      git_status = git_status,
      base = base,
      git_status_diff_base = git_status_diff_base,
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

---Defaults to arguements that list all untracked/ignored files individually.
---@param worktree_root string
---@param porcelain_version 1|2
---@param opts neotree.git._StatusCommandArgs?
---@return string[] args
local make_git_status_args = function(porcelain_version, worktree_root, opts)
  opts = opts or {}
  opts.ignored = opts.ignored or "traditional"
  opts.untracked_files = opts.untracked_files or "normal"
  local args = {
    "--no-optional-locks",
    "-C",
    worktree_root,
    "status",
    porcelain_flag[porcelain_version],
    "-z",
    "--ignored=" .. opts.ignored,
    "--untracked-files=" .. opts.untracked_files,
  }
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
---@param path string? git ref base
---@param base_lookup neotree.git.BaseLookup? git ref base
---@param skip_bubbling boolean? Whether to skip bubling up status to directories
---@param status_opts neotree.git._StatusCommandArgs? Path to run the git status command in, defaults to cwd.
---@return neotree.git.Status? git_status the neotree.Git.Status of the given root, if there's a valid git status there
---@return string? worktree_root
---@return neotree.git.Status? git_status_diff_vs_base
M.status = function(path, base_lookup, skip_bubbling, status_opts)
  path = path or assert(uv.cwd())
  local worktree_root, git_dir, superproject_worktree_root = M.find_worktree_info(path)
  if not worktree_root then
    if not git_dir then
      invalidate_upward_worktrees(path)
    end
    return nil, nil
  end

  ---@cast worktree_root -nil
  local status_porcelain_version = get_status_porcelain_version()
  if not status_porcelain_version then
    return nil, nil
  end
  try_register_worktree(
    worktree_root,
    log.assert(git_dir, "git dir not found for worktree_root %s", worktree_root),
    superproject_worktree_root
  )
  local status_cmd = {
    "git",
    unpack(make_git_status_args(status_porcelain_version, worktree_root, status_opts)),
  }

  local raw_status_text = vim.fn.system(status_cmd)
  assert(vim.v.shell_error == 0)

  local last_status_text = raw_status_text_cache[worktree_root]
  local status_text = raw_status_text:gsub("\001", "\000") -- to make the following cache check work
  if status_text == last_status_text then
    -- return the current status
    return M.worktrees[worktree_root].status, worktree_root
  end
  raw_status_text_cache[worktree_root] = status_text

  skip_bubbling = not not skip_bubbling
  local status_iter = utils.gsplit_plain(status_text, "\000")
  local git_status = parser.parse_status_porcelain(
    status_porcelain_version,
    worktree_root,
    status_iter,
    skip_bubbling
  )

  local git_status_over_base
  if base_lookup and base_lookup[worktree_root] then
    git_status_over_base = require("neo-tree.git.diff").diff_name_status(
      worktree_root,
      base_lookup[worktree_root],
      skip_bubbling
    )
  end
  change_worktree_git_status(
    worktree_root,
    git_status,
    base_lookup and base_lookup[worktree_root],
    git_status_over_base
  )
  return git_status, worktree_root, git_status_over_base
end

---Creates a job for `git status`
---@param context neotree.git.JobContext
---@param git_args string[]? nil to use default of make_git_status_args, which includes all files
---@param on_parsed fun(gs: neotree.git.Status)
---@param skip_bubbling boolean?
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
    local past_raw_status_text = raw_status_text_cache[context.worktree_root]
    if status_text == past_raw_status_text then
      -- stdout text did not change.
      return
    end
    raw_status_text_cache[context.worktree_root] = status_text

    local status_iter = utils.gsplit_plain(status_text, "\000")
    local parsing_task = co.create(parser.parse_status_porcelain)
    local first_output = {
      log.assert(
        co.resume(
          parsing_task,
          context.porcelain_version,
          context.worktree_root,
          status_iter,
          skip_bubbling,
          context
        )
      ),
    }
    git_utils.parse_in_batches(parsing_task, context, first_output, on_parsed)
  end)
end

---Runs `git status` asynchronously, will update neo-tree once finished.
---@param path string path to run commands in
---@param base_lookup neotree.git.BaseLookup? git ref base
---@param opts neotree.Config.GitStatusAsync
M.status_async = function(path, base_lookup, opts)
  M.find_worktree_info(path, function(worktree_root, git_dir, superproject_worktree_root)
    if not worktree_root then
      log.trace("status_async: not a git folder:", path)
      if not git_dir then
        invalidate_upward_worktrees(path)
      end
      return
    end

    try_register_worktree(worktree_root, git_dir, superproject_worktree_root)

    log.trace("git.status_async called for", worktree_root)

    local event_id = "git_status_async@" .. worktree_root
    utils.debounce(event_id, function()
      vim.schedule(function()
        local git_status_porcelain_version = get_status_porcelain_version()
        if not git_status_porcelain_version then
          return
        end
        ---@class neotree.git.JobContext
        ---@field git_status neotree.git.Status
        local ctx = {
          porcelain_version = git_status_porcelain_version,
          worktree_root = worktree_root,
          git_status = {},
          num_in_batch = 0,
          lines_parsed = 0,
          batch_size = opts.batch_size or 1000,
          batch_delay = opts.batch_delay or 10,
          max_lines = opts.max_lines or 100000,
        }
        local existing_worktree = M.worktrees[ctx.worktree_root]
        local base = base_lookup and base_lookup[worktree_root]
        if existing_worktree and existing_worktree.status then
          git_status_job(ctx, nil, function(full_status)
            change_worktree_git_status(worktree_root, full_status)
          end)
          if base then
            git_diff.diff_name_status_job(worktree_root, base, false, ctx, function(status)
              change_worktree_git_status(worktree_root, existing_worktree.status, base, status)
            end)
          end
          return
        end

        -- do a fast scan first to get basic things in
        local fast_args = make_git_status_args(git_status_porcelain_version, worktree_root, {
          untracked_files = "no",
        })
        git_status_job(ctx, fast_args, function(fast_status)
          change_worktree_git_status(worktree_root, fast_status)

          if base then
            git_diff.diff_name_status_job(worktree_root, base, false, ctx, function(status)
              change_worktree_git_status(worktree_root, ctx.git_status, base, status)
            end)
          end
          -- Get ignored statuses
          git_ls_files.ignored_job(ctx, function(ignored_paths)
            for _, ignored_path in ipairs(ignored_paths) do
              ctx.git_status[ignored_path] = "!"
            end
            change_worktree_git_status(worktree_root, ctx.git_status)
          end)

          -- Check for showUntrackedFiles and rescan for the full status
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
                change_worktree_git_status(worktree_root, full_status)
              end)
            end
          )
        end)
      end)
    end, 1000, utils.debounce_strategy.CALL_FIRST_AND_LAST, utils.debounce_action.START_ASYNC_JOB)
  end)
end

---@param path string
---@param stdout_lines string[]
---@return string[] normalized_stdout_paths
local process_output = function(path, stdout_lines)
  local lines = stdout_lines
  for i, p in ipairs(stdout_lines) do
    if #p == 0 then
      lines[i] = nil
    end

    if utils.is_windows then
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
local find_worktree_info_slow = function(path, callback)
  local base_args = {
    "-C",
    path,
    "rev-parse",
  }
  ---@type string[][]
  local argument_lists = {}
  for _, arg in ipairs({
    "--absolute-git-dir",
    "--show-toplevel",
    "--show-superproject_worktree_root",
  }) do
    local args = { unpack(base_args) }
    args[#args + 1] = arg
    argument_lists[#argument_lists + 1] = args
  end

  local git_dir = vim.fn.system({ "git", unpack(argument_lists[1]) })
  local worktree_root = vim.fn.system({ "git", unpack(argument_lists[2]) })
  local superproject_worktree_root = vim.fn.system({ "git", unpack(argument_lists[3]) })
  local paths = { worktree_root, git_dir, superproject_worktree_root }
  for i, p in ipairs(paths) do
    if #p == 0 or vim.startswith(p, "fatal:") then
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
---@return string? git_dir
---@return string? worktree_root
---@return string? superproject_worktree_root
M.find_worktree_info = function(path, callback)
  path = path or log.assert(uv.cwd())

  if path:find("\n", 1, true) then
    return find_worktree_info_slow(path, callback)
  end

  local rev_parse_args = {
    "-C",
    path,
    "rev-parse",

    "--absolute-git-dir", -- the order is this because absolute-git-dir won't fail in the git dir, but show-toplevel will.
    "--show-toplevel", -- stdout if in worktree, stderr if in git dir, nothing if neither
    "--show-superproject-working-tree", -- stdout if in submodule, nothing if neither
  }

  if callback then
    log.assert(type(callback) == "function", "callback for find_worktree_info should be a function")
    git_utils.git_job(rev_parse_args, function(code, stdout_chunks, stderr_chunks)
      local full_stdout = table.concat(stdout_chunks, "")
      local stdout_lines = {}
      for line in utils.gsplit_plain(full_stdout, "\n") do
        stdout_lines[#stdout_lines + 1] = line
      end
      local info = process_output(path, stdout_lines)
      local git_dir, worktree_root, superproject_worktree_root = unpack(info)
      callback(worktree_root, git_dir, superproject_worktree_root)
    end)
    return
  end

  local ok, rev_parse_lines = utils.execute_command({ "git", unpack(rev_parse_args) })
  local info = process_output(path, rev_parse_lines)
  local git_dir, worktree_root, superproject_worktree_root = unpack(info)
  return worktree_root, git_dir, superproject_worktree_root
end

---@type table<string, string|false>
M._upward_worktree_cache = setmetatable({}, weak_kv)

---Given a normalized path, find a known worktree upwards of it.
---@param path string
---@return string? worktree_root
---@return neotree.git.WorktreeInfo? worktree_info
M.find_existing_worktree = function(path)
  local cached = M._upward_worktree_cache[path]
  if cached ~= nil then
    local worktree = cached and M.worktrees[cached]
    return cached or nil, worktree and worktree
  end
  for worktree_root, worktree in pairs(M.worktrees) do
    if utils.is_subpath(worktree_root, path, true) then
      M._upward_worktree_cache[path] = worktree_root
      return worktree_root, worktree
    end
  end
  M._upward_worktree_cache[path] = false
end

---@param state neotree.State
---@param items neotree.FileItem[]
M.mark_gitignored = function(state, items)
  local upward_status = false
  local statuses = {}
  for worktree_root, worktree in pairs(M.worktrees) do
    statuses[worktree_root] = worktree.status
    if utils.is_subpath(worktree_root, state.path, true) then
      upward_status = true
    end
  end

  if not upward_status and git_utils.might_be_in_git_repo(state.path) then
    local worktree_root = M.find_worktree_info(state.path)
    if not worktree_root then
      return
    end

    local ignored_list = git_ls_files.ignored(worktree_root)
    local status = {}
    for _, path in ipairs(ignored_list) do
      status[path] = "!"
    end
    statuses[worktree_root] = status
  end

  for _, i in ipairs(items) do
    for worktree_root, git_status in pairs(statuses) do
      local path = i.path
      if utils.is_subpath(worktree_root, path, true) then
        local status = git_status[path]
        ---@type string?
        local parent = path
        while not status do
          parent = utils.split_path(parent)
          if #parent <= #worktree_root then
            break
          end
          status = git_status[parent]
        end
        if status == "!" then
          i.filtered_by = i.filtered_by or {}
          i.filtered_by.gitignored = true
          break
        end
      end
    end
  end
end

---@param git_status neotree.git.Status
---@param worktree_root string
---@param path string
---@return neotree.git.StatusCode?
local function find_status_code_in_git_status(git_status, worktree_root, path)
  local status = git_status[path]
  if status then
    return status
  end

  ---Check parents to see if the path is in a dir marked as untracked/ignored
  ---@type string?
  local parent = path
  while not status do
    parent = utils.split_path(parent)
    if #parent < #worktree_root then
      break
    end
    status = git_status[parent]
  end

  if status == "!" or status == "?" then
    return status
  end

  return nil
end

---Given a normalized path, find the existing status code for it.
---@param path string A normalized path.
---@param base_lookup neotree.git.BaseLookup? Whether to also look up the status from a base
---@return neotree.git.StatusCode? status_code
---@return boolean? status_from_base Whether the status was from a diff vs another commit.
M.find_existing_status_code = function(path, base_lookup)
  local worktree_root, worktree = M.find_existing_worktree(path)
  if not worktree or not worktree_root then
    return nil
  end

  local worktree_git_status = worktree.status

  if worktree_git_status then
    local worktree_status_code =
      find_status_code_in_git_status(worktree_git_status, worktree_root, path)
    if worktree_status_code then
      return worktree_status_code, false
    end
  end

  if base_lookup then
    local base = base_lookup[worktree_root]
    local diff_status = base and worktree.status_diff[base]
    if diff_status then
      local diff_status_code = find_status_code_in_git_status(diff_status, worktree_root, path)
      if diff_status_code then
        return diff_status_code, true
      end
    end
  end
  return nil, nil
end

return M
