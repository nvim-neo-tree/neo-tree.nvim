local utils = require("neo-tree.utils")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local Job = require("plenary.job")
local uv = vim.uv or vim.loop
local co = coroutine

local M = {}
local gsplit_plain = vim.fn.has("nvim-0.9") == 1 and { plain = true } or true
local git_available, git_version_output = utils.execute_command({ "git", "--version" })
local git_version
if git_available then
  ---@diagnostic disable-next-line: param-type-mismatch
  local version_output = vim.split(git_version_output[1], ".", gsplit_plain)
  git_version = {
    major = tonumber(version_output[1]:sub(#"git version " + 1)),
    minor = tonumber(version_output[2]),
    patch = tonumber(version_output[3] or 0),
  }
end

local has_porcelain_v2 = git_version and git_version.major >= 2 and git_version.minor >= 12
M._supported_porcelain_version = has_porcelain_v2 and 2 or 1

---@type table<string, neotree.git.Status>
M.status_cache = setmetatable({}, {
  __mode = "kv",
})

---@class (exact) neotree.git.Context : neotree.Config.GitStatusAsync
---@field git_status neotree.git.Status?
---@field git_root string

---@alias neotree.git.Status table<string, string>

---@param context neotree.git.Context
---@param git_status neotree.git.Status?
local update_git_status = function(context, git_status)
  context.git_status = git_status
  M.status_cache[context.git_root] = git_status
  vim.schedule(function()
    events.fire_event(events.GIT_STATUS_CHANGED, {
      git_root = context.git_root,
      git_status = context.git_status,
    })
  end)
end

---@param path string
---@return string path_with_no_trailing_slash
local trim_trailing_slash = function(path)
  return path:sub(-1, -1) == "/" and path:sub(1, -2) or path
end

local COMMENT_BYTE = ("#"):byte()
local TYPE_ONE_BYTE = ("1"):byte()
local TYPE_TWO_BYTE = ("2"):byte()
local UNMERGED_BYTE = ("u"):byte()
local UNTRACKED_BYTE = ("?"):byte()
local IGNORED_BYTE = ("!"):byte()
local parent_cache = setmetatable({}, {
  __mode = "kv",
})
---@param porcelain_version 1|2
---@param status_iter fun():string? A function that will override each var of the git status
---@param git_status neotree.git.Status? The git status table to override, if any
---@param batch_size integer? This will use coroutine.yield if non-nil and > 0.
---@param skip_bubbling boolean?
---@return neotree.git.Status
M._parse_porcelain = function(
  porcelain_version,
  git_root,
  status_iter,
  git_status,
  batch_size,
  skip_bubbling
)
  local git_root_dir = utils.normalize_path(git_root)
  if not vim.endswith(git_root_dir, utils.path_separator) then
    git_root_dir = git_root_dir .. utils.path_separator
  end

  local num_in_batch = 0
  git_status = git_status or {}
  if not batch_size or batch_size <= 0 then
    batch_size = nil
  end
  local yield_if_batch_completed

  if batch_size then
    yield_if_batch_completed = function()
      num_in_batch = num_in_batch + 1
      if num_in_batch > batch_size then
        coroutine.yield(git_status)
        num_in_batch = 0
      end
    end
  end

  local line = status_iter()

  ---@type string[]
  local statuses = {}
  ---@type string[]
  local paths = {}

  if porcelain_version == 1 then
    while line do
      -- Example status:
      -- D  deleted_staged.txt
      --  D deleted_unstaged.txt
      -- MM modified_mixed.txt
      -- M  modified_staged.txt
      --  M modified_unstaged.txt
      -- A  new_staged_file.txt
      -- R  renamed_staged_old.txt -> renamed_staged_new.txt
      --  T type_change.txt
      -- ?? .gitignore
      -- ?? untracked.txt
      -- !! ignored.txt
      local XY = line:sub(1, 2)
      if XY == "??" or XY == "!!" then
        break
      end

      if XY ~= "# " then
        local X = XY:sub(1, 1)
        local Y = XY:sub(2, 2)
        local path = line:sub(4)
        if X == "R" or Y == "R" or X == "C" or Y == "C" then
          status_iter() -- consume original path
        end
        local abspath = git_root_dir .. path
        if utils.is_windows then
          abspath = utils.windowize_path(abspath)
        end
        paths[#paths + 1] = abspath
      end
      line = status_iter()
      if batch_size then
        yield_if_batch_completed()
      end
    end
  elseif porcelain_version == 2 then
    while line do
      -- Example status:
      -- 1 D. N... 100644 000000 000000 ade2881afa1dcb156a3aa576024aa0fecf789191 0000000000000000000000000000000000000000 deleted_staged.txt
      -- 1 .D N... 100644 100644 000000 9c13483e67ceff219800303ec7af39c4f0301a5b 9c13483e67ceff219800303ec7af39c4f0301a5b deleted_unstaged.txt
      -- 1 MM N... 100644 100644 100644 4417f3aca512ffdf247662e2c611ee03ff9255cc 29c0e9846cd6410a44c4ca3fdaf5623818bd2838 modified_mixed.txt
      -- 1 M. N... 100644 100644 100644 f784736eecdd43cd8eb665615163cfc6506fca5f 8d6fad5bd11ac45c7c9e62d4db1c427889ed515b modified_staged.txt
      -- 1 .M N... 100644 100644 100644 c9e1e027aa9430cb4ffccccf45844286d10285c1 c9e1e027aa9430cb4ffccccf45844286d10285c1 modified_unstaged.txt
      -- 1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 89cae60d74c222609086441e29985f959b6ec546 new_staged_file.txt
      -- 2 R. N... 100644 100644 100644 3454a7dc6b93d1098e3c3f3ec369589412abdf99 3454a7dc6b93d1098e3c3f3ec369589412abdf99 R100 renamed_staged_new.txt
      -- renamed_staged_old.txt
      -- 1 .T N... 100644 100644 120000 192f10ed8c11efb70155e8eb4cae6ec677347623 192f10ed8c11efb70155e8eb4cae6ec677347623 type_change.txt
      -- ? .gitignore
      -- ? untracked.txt
      -- ! ignored.txt

      -- 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
      -- 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><sep><origPath>
      local line_type_byte = line:byte(1, 1)
      if line_type_byte == COMMENT_BYTE then
      -- continue for now
      elseif line_type_byte == TYPE_ONE_BYTE then
        local XY = line:sub(3, 4)
        -- local submodule_state = line:sub(6, 9)
        -- local mH = line:sub(11, 16)
        -- local mI = line:sub(18, 23)
        -- local mW = line:sub(25, 30)
        -- local hH = line:sub(32, 71)
        -- local hI = line:sub(73, 112)
        local path = line:sub(114)

        local abspath = git_root_dir .. path
        if utils.is_windows then
          abspath = utils.windowize_path(abspath)
        end
        paths[#paths + 1] = abspath
        statuses[#statuses + 1] = XY
      elseif line_type_byte == TYPE_TWO_BYTE then
        local XY = line:sub(3, 4)
        -- local submodule_state = line:sub(6, 9)
        -- local mH = line:sub(11, 16)
        -- local mI = line:sub(18, 23)
        -- local mW = line:sub(25, 30)
        -- local hH = line:sub(32, 71)
        -- local hI = line:sub(73, 112)
        -- local rest = line:sub(114)
        -- local Xscore = rest:sub(1, first_space - 1)
        local first_space = line:find(" ", 114, true)
        local path = line:sub(first_space + 1)

        local abspath = git_root_dir .. path
        if utils.is_windows then
          abspath = utils.windowize_path(abspath)
        end
        paths[#paths + 1] = abspath
        statuses[#statuses + 1] = XY
        -- ignore the original path
        status_iter()
      elseif line_type_byte == UNMERGED_BYTE then
        local XY = line:sub(3, 4)
        -- local submodule_state = line:sub(6, 9)
        -- local m1 = line:sub(11, 16)
        -- local m2 = line:sub(18, 23)
        -- local m3 = line:sub(25, 30)
        -- local mW = line:sub(32, 37)
        -- local h1 = line:sub(39, 78)
        -- local h2 = line:sub(80, 119)
        -- local h3 = line:sub(121, 160)
        local path = line:sub(162)

        local abspath = git_root_dir .. path
        if utils.is_windows then
          abspath = utils.windowize_path(abspath)
        end
        paths[#paths + 1] = abspath
        statuses[#statuses + 1] = XY
      else
        -- either untracked or ignored
        break
      end
      if batch_size then
        yield_if_batch_completed()
      end
      line = status_iter()
    end
  end

  local path_start = porcelain_version == 2 and 3 or 4

  -- -------------------------------------------------
  -- ?           ?    untracked
  -- !           !    ignored
  -- -------------------------------------------------
  while line and line:byte(1, 1) == UNTRACKED_BYTE do
    local abspath = git_root_dir .. trim_trailing_slash(line:sub(path_start))
    if utils.is_windows then
      abspath = utils.windowize_path(abspath)
    end
    git_status[abspath] = "?"
    line = status_iter()
    if batch_size then
      yield_if_batch_completed()
    end
  end

  for i, p in ipairs(paths) do
    git_status[p] = statuses[i]
  end

  if not skip_bubbling then
    local conflicts = {}
    local untracked = {}
    local modified = {}
    local added = {}
    local deleted = {}
    local typechanged = {}
    local renamed = {}
    local copied = {}
    for i, s in ipairs(statuses) do
      if s:find("U", 1, true) then
        conflicts[#conflicts + 1] = i
      elseif s:find("?", 1, true) then
        untracked[#untracked + 1] = i
      elseif s:find("M", 1, true) then
        modified[#modified + 1] = i
      elseif s:find("A", 1, true) then
        added[#added + 1] = i
      elseif s:find("D", 1, true) then
        deleted[#deleted + 1] = i
      elseif s:find("T", 1, true) then
        typechanged[#typechanged + 1] = i
      elseif s:find("R", 1, true) then
        renamed[#renamed + 1] = i
      elseif s:find("C", 1, true) then
        copied[#copied + 1] = i
      end
    end
    local flattened = {}

    for _, list in ipairs({
      conflicts,
      untracked,
      modified,
      added,
      deleted,
      typechanged,
      renamed,
      copied,
    }) do
      require("neo-tree.utils._compat").table_move(list, 1, #list, #flattened, flattened)
    end

    local parent_statuses = {}
    do
      for _, i in ipairs(flattened) do
        local path = paths[i]
        local status = statuses[i]
        local parent
        repeat
          local cached = parent_cache[path]
          if cached then
            parent = cached
          else
            parent = utils.split_path(path)
            if parent then
              parent_cache[path] = parent
            else
              break
            end
          end

          if #git_root >= #parent then
            break
          end
          if parent_statuses[parent] ~= nil then
            break
          end

          parent_statuses[parent] = status
          path = parent
        until false

        if batch_size then
          yield_if_batch_completed()
        end
      end
      for parent, status in pairs(parent_statuses) do
        git_status[parent] = status
      end
    end
  end

  while line and line:sub(1, 1) == IGNORED_BYTE do
    local abspath = git_root_dir .. trim_trailing_slash(line:sub(path_start))
    if utils.is_windows then
      abspath = utils.windowize_path(abspath)
    end
    git_status[abspath] = "!"
    line = status_iter()

    if batch_size then
      yield_if_batch_completed()
    end
  end

  M.status_cache[git_root] = git_status
  return git_status
end

---@param git_root string
---@param porcelain_version 1|2
---@param untracked_files "all"|"no"|"normal"?
---@param ignored "traditional"|"no"|"matching"?
---@param paths string[]?
---@return string[] args
local make_git_status_args = function(porcelain_version, git_root, untracked_files, ignored, paths)
  untracked_files = untracked_files or "normal"
  ignored = ignored or "traditional"
  local opts = {
    "--no-optional-locks",
    "-C",
    git_root,
    "status",
    "--porcelain=v" .. porcelain_version,
    "--untracked-files=" .. untracked_files,
    "--ignored=" .. ignored,
    "-z",
    "--",
  }
  if paths then
    for _, path in ipairs(paths) do
      opts[#opts + 1] = path
    end
  end
  return opts
end

---Parse "git status" output for the current working directory.
---@param base string git ref base
---@param skip_bubbling boolean? Whether to skip bubling up status to directories
---@param path string? Path to run the git status command in, defaults to cwd.
---@return neotree.git.Status?, string? git_status the neotree.Git.Status of the given root, if there's a valid git status there
M.status = function(base, skip_bubbling, path)
  local git_root = M.get_worktree_root(path)
  if not utils.truthy(git_root) then
    return nil
  end
  ---@cast git_root -nil

  local status_cmd = {
    "git",
    unpack(make_git_status_args(M._supported_porcelain_version, git_root)),
  }
  local status_result = vim.fn.system(status_cmd)

  local status_ok = vim.v.shell_error == 0
  ---@type neotree.git.Context
  local context = {
    git_root = git_root,
    git_status = nil,
    lines_parsed = 0,
  }

  if status_ok then
    -- system() replaces \000 with \001
    ---@diagnostic disable-next-line: param-type-mismatch
    local status_iter = vim.gsplit(status_result, "\001", gsplit_plain)
    local git_status = M._parse_porcelain(
      M._supported_porcelain_version,
      git_root,
      status_iter,
      nil,
      nil,
      skip_bubbling
    )

    update_git_status(context, git_status)
  end

  return context.git_status, git_root
end

---@param context neotree.git.Context
---@param git_args string[]? nil to use default of make_git_status_args, which includes all files
---@param callback fun(gs: neotree.git.Status)
---@param skip_bubbling boolean?
local async_git_status_job = function(context, git_args, callback, skip_bubbling)
  local stdin = log.assert(uv.new_pipe())
  local stdout = log.assert(uv.new_pipe())
  local stderr = log.assert(uv.new_pipe())

  local output_chunks = {}
  ---@diagnostic disable-next-line: missing-fields
  uv.spawn("git", {
    hide = true,
    args = git_args or make_git_status_args(M._supported_porcelain_version, context.git_root),
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    stdin:shutdown()
    stdin:close()
    stdout:shutdown()
    stdout:close()
    stderr:shutdown()
    stderr:close()
    if code ~= 0 then
      log.at.warn.format(
        "git status async process exited abnormally, code: %s, signal: %s",
        code,
        signal
      )
      return
    end

    local output = output_chunks[1]
    if #output_chunks > 1 then
      output = table.concat(output_chunks, "")
    end
    if not output then
      callback(context.git_status)
      return
    end

    ---@diagnostic disable-next-line: param-type-mismatch
    local status_iter = vim.gsplit(output, "\000", gsplit_plain)
    local parsing_task = co.create(M._parse_porcelain)
    log.assert(
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
      if co.status(parsing_task) ~= "dead" then
        processed_lines = processed_lines + context.batch_size
        if processed_lines < context.max_lines then
          log.assert(co.resume(parsing_task))
          vim.defer_fn(do_next_batch_later, context.batch_delay)
          return
        end
      end
      callback(context.git_status)
    end
    do_next_batch_later()
  end)
  stdout:read_start(function(err, data)
    log.assert(not err, err)
    -- for some reason data can be a table here?
    if type(data) == "string" then
      table.insert(output_chunks, data)
    end
  end)

  stderr:read_start(function(err, data)
    log.assert(not err, err)
    if err then
      local errfmt = (err or "") .. "%s"
      log.at.error.format(errfmt, data)
    end
  end)
end

---@param path string path to run commands in
---@param base string git ref base
---@param opts neotree.Config.GitStatusAsync
M.status_async = function(path, base, opts)
  M.get_worktree_root(path, function(git_root)
    if not git_root then
      log.trace("status_async: not a git folder:", path)
      return
    end

    log.trace("git.status_async called")

    local event_id = "git_status_" .. git_root

    utils.debounce(event_id, function()
      ---@type neotree.git.Context
      local ctx = {
        git_root = git_root,
        git_status = {},
        batch_size = opts.batch_size or 1000,
        batch_delay = opts.batch_delay or 10,
        max_lines = opts.max_lines or 100000,
      }
      if not M.status_cache[ctx.git_root] then
        -- do a fast scan first to get basic things in, then a full scan with untracked files
        async_git_status_job(
          ctx,
          make_git_status_args(
            M._supported_porcelain_version,
            git_root,
            "no",
            "traditional",
            { path }
          ),
          function(fast_status)
            update_git_status(ctx, fast_status)
            async_git_status_job(ctx, nil, function(full_status)
              update_git_status(ctx, full_status)
            end, true)
          end
        )
      else
        async_git_status_job(ctx, nil, function(full_status)
          update_git_status(ctx, full_status)
        end)
      end
    end, 1000, utils.debounce_strategy.CALL_FIRST_AND_LAST, utils.debounce_action.START_ASYNC_JOB)
  end)
end

---@param state neotree.State
---@param items neotree.FileItem[]
M.mark_ignored = function(state, items)
  local gs = state.git_status_lookup
  if not gs then
    return
  end
  for _, i in ipairs(items) do
    local direct_lookup = gs[i.path]
    if direct_lookup == "!" then
      i.filtered_by = i.filtered_by or {}
      i.filtered_by.gitignored = true
    end
  end
end

local sp = utils.split_path
---Invalidate cache for path and parents, updating trees as needed
---@param path string
local invalidate_cache = function(path)
  ---@type string?
  local parent = sp(path)

  while parent do
    local cache_entry = M.status_cache[parent]
    if cache_entry ~= nil then
      update_git_status({ git_root = parent }, nil)
    end
    parent = sp(parent)
  end
end

---Returns the repository root, already normalized.
---@param path string? Defaults to cwd
---@param callback fun(git_root: string?)?
---@return string?
M.get_worktree_root = function(path, callback)
  path = path or log.assert(uv.cwd())

  local args = { "-C", path, "rev-parse", "--show-toplevel" }

  if type(callback) == "function" then
    ---@diagnostic disable-next-line: missing-fields
    Job:new({
      command = "git",
      args = args,
      enabled_recording = true,
      on_exit = function(self, code, _)
        if code ~= 0 then
          log.trace("GIT ROOT ERROR", self:stderr_result())
          invalidate_cache(path)
          callback(nil)
          return
        end
        local git_root = self:result()[1]
        if git_root then
          git_root = utils.normalize_path(git_root)
        end

        callback(git_root)
      end,
    }):start()
    return
  end

  local ok, git_output = utils.execute_command({ "git", unpack(args) })
  if not ok then
    log.trace("GIT ROOT NOT FOUND", git_output)
    invalidate_cache(path)
    return nil
  end
  local git_root = git_output[1]
  if git_root then
    git_root = utils.normalize_path(git_root)
  end

  return git_root
end

---Returns the absolute git dir path
---@param path string? Defaults to cwd
---@param callback fun(git_root: string?)?
---@return string?
M.get_git_dir = function(path, callback)
  path = path or log.assert(uv.cwd())

  local args = { "-C", path, "rev-parse", "--absolute-git-dir" }

  if type(callback) == "function" then
    ---@diagnostic disable-next-line: missing-fields
    Job:new({
      command = "git",
      args = args,
      enabled_recording = true,
      on_exit = function(self, code, _)
        if code ~= 0 then
          log.trace("GIT DIR ERROR", self:stderr_result())
          invalidate_cache(path)
          callback(nil)
          return
        end
        local git_root = self:result()[1]
        if git_root then
          git_root = utils.normalize_path(git_root)
        end

        callback(git_root)
      end,
    }):start()
    return
  end

  local ok, git_output = utils.execute_command({ "git", unpack(args) })
  if not ok then
    log.trace("GIT ROOT NOT FOUND", git_output)
    invalidate_cache(path)
    return nil
  end
  local git_root = git_output[1]
  if git_root then
    git_root = utils.normalize_path(git_root)
  end

  return git_root
end

return M
