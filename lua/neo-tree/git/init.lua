local utils = require("neo-tree.utils")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local Job = require("plenary.job")
local uv = vim.uv or vim.loop
local co = coroutine

local M = {}
local gsplit_plain = vim.fn.has("nvim-0.9") == 1 and { plain = true } or true
local git_available, git_version_output = utils.execute_command({ "git", "--version" })
local git_version_major, git_version_minor
if git_available then
  ---@diagnostic disable-next-line: param-type-mismatch
  local version_numbers = vim.split(git_version_output[1], ".", gsplit_plain)
  git_version_major = version_numbers[1]:sub(#"git version " + 1)
  git_version_minor = version_numbers[2]
end

---@type table<string, neotree.git.Status>
M.status_cache = setmetatable({}, {
  __mode = "v",
  __newindex = function(self, root_dir, status)
    require("neo-tree.sources.filesystem.lib.fs_watch").on_destroyed(root_dir, function()
      rawset(self, root_dir, nil)
      events.fire_event(events.GIT_STATUS_CHANGED, { git_root = root_dir, status = status })
    end)
    rawset(self, root_dir, status)
  end,
})

---@class (exact) neotree.git.Context : neotree.Config.GitStatusAsync
---@field git_status neotree.git.Status?
---@field git_root string

---@alias neotree.git.Status table<string, string>

---@param ctx neotree.git.Context
---@param git_status neotree.git.Status
local update_git_status = function(ctx, git_status)
  ctx.git_status = git_status
  M.status_cache[ctx.git_root] = git_status
  vim.schedule(function()
    events.fire_event(events.GIT_STATUS_CHANGED, {
      git_root = ctx.git_root,
      git_status = ctx.git_status,
    })
  end)
end

---@param git_root string
---@param status_iter fun():string? A function that will override each var of the git status
---@param git_status neotree.git.Status? The git status table to override, if any
---@param batch_size integer? This will use coroutine.yield if non-nil and > 0.
---@param skip_bubbling boolean?
---@return neotree.git.Status
M.parse_porcelain_output = function(git_root, status_iter, git_status, batch_size, skip_bubbling)
  local git_root_dir = utils.normalize_path(git_root) .. utils.path_separator
  local prev_line = ""
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
  for line in status_iter do
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

    -- 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
    -- 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><sep><origPath>
    local t = line:sub(1, 1)
    if t == "1" then
      local XY = line:sub(3, 4)
      -- local submodule_state = line:sub(6, 9)
      -- local mH = line:sub(11, 16)
      -- local mI = line:sub(18, 23)
      -- local mW = line:sub(25, 30)
      -- local hH = line:sub(32, 71)
      -- local hI = line:sub(73, 112)
      local path = line:sub(114)
      git_status[git_root_dir .. path] = XY
    elseif t == "2" then
      -- local XY = line:sub(3, 4)
      -- local submodule_state = line:sub(6, 9)
      -- local mH = line:sub(11, 16)
      -- local mI = line:sub(18, 23)
      -- local mW = line:sub(25, 30)
      -- local hH = line:sub(32, 71)
      -- local hI = line:sub(73, 112)
      local rest = line:sub(114)
      local first_space = rest:find(" ", 1, true)
      local Xscore = rest:sub(1, first_space - 1)
      local path = rest:sub(first_space + 1)
      git_status[git_root_dir .. path] = Xscore
      -- ignore the original path
      status_iter()
    elseif t == "u" then
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
      git_status[git_root_dir .. path] = XY
    else
      prev_line = line
      break
    end
    -- X          Y     Meaning
    -- -------------------------------------------------
    -- 	        [AMD]   not updated
    -- M        [ MTD]  updated in index
    -- T        [ MTD]  type changed in index
    -- A        [ MTD]  added to index
    -- D                deleted from index
    -- R        [ MTD]  renamed in index
    -- C        [ MTD]  copied in index
    -- [MTARC]          index and work tree matches
    -- [ MTARC]    M    work tree changed since index
    -- [ MTARC]    T    type changed in work tree since index
    -- [ MTARC]    D    deleted in work tree
    --             R    renamed in work tree
    --             C    copied in work tree
    -- -------------------------------------------------
    -- D           D    unmerged, both deleted
    -- A           U    unmerged, added by us
    -- U           D    unmerged, deleted by them
    -- U           A    unmerged, added by them
    -- D           U    unmerged, deleted by us
    -- A           A    unmerged, both added
    -- U           U    unmerged, both modified
    if batch_size then
      yield_if_batch_completed()
    end
  end

  -- -------------------------------------------------
  -- ?           ?    untracked
  -- !           !    ignored
  -- -------------------------------------------------
  if prev_line:sub(1, 1) == "?" then
    git_status[git_root_dir .. prev_line:sub(3)] = "?"
    for line in status_iter do
      if line:sub(1, 1) ~= "?" then
        prev_line = line
        break
      end
      git_status[git_root_dir .. line:sub(3)] = "?"
    end
    if batch_size then
      yield_if_batch_completed()
    end
  end

  if not skip_bubbling then
    -- bubble up every status besides ignored
    local status_prio = { "U", "?", "M", "A", "D", "T", "R", "C" }

    for dir, status in pairs(git_status) do
      if status ~= "!" then
        local s1 = status:sub(1, 1)
        local s2 = status:sub(2, 2)
        for parent in utils.path_parents(dir, true) do
          if parent == git_root then
            -- bubble only up to the children of the git root
            break
          end

          local parent_status = git_status[parent]
          if not parent_status then
            git_status[parent] = status
          else
            -- Bubble up the most important status
            local p = parent_status:sub(1, 1)
            for _, c in ipairs(status_prio) do
              if p == c then
                break
              end
              if s1 == c or s2 == c then
                git_status[parent] = c
              end
            end
          end
        end
      end
      if batch_size then
        yield_if_batch_completed()
      end
    end
  end

  if prev_line:sub(1, 1) == "!" then
    git_status[git_root_dir .. prev_line:sub(3)] = "!"
    for line in status_iter do
      git_status[git_root_dir .. line:sub(3)] = "!"
    end
    if batch_size then
      yield_if_batch_completed()
    end
  end

  M.status_cache[git_root] = git_status
  return git_status
end
---@param git_root string
---@param untracked_files "all"|"no"|"normal"?
---@param ignored "traditional"|"no"|"matching"?
---@param paths string[]?
---@return string[] args
local make_git_status_args = function(git_root, untracked_files, ignored, paths)
  untracked_files = untracked_files or "normal"
  ignored = ignored or "traditional"
  local opts = {
    "--no-optional-locks",
    "-C",
    git_root,
    "status",
    "--porcelain=v2",
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
  local git_root = M.get_repository_root(path)
  if not utils.truthy(git_root) then
    return nil
  end
  ---@cast git_root -nil

  local status_cmd = {
    "git",
    unpack(make_git_status_args(git_root)),
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
    local git_status = M.parse_porcelain_output(git_root, status_iter, nil, nil, skip_bubbling)

    update_git_status(context, git_status)
  end

  return context.git_status, git_root
end

---@param context neotree.git.Context
---@param git_args string[]? nil to use default of make_git_status_args, which includes all files
---@param callback fun(gs: neotree.git.Status)
local async_git_status_job = function(context, git_args, callback)
  local stdin = log.assert(uv.new_pipe())
  local stdout = log.assert(uv.new_pipe())
  local stderr = log.assert(uv.new_pipe())

  local output_chunks = {}
  ---@diagnostic disable-next-line: missing-fields
  uv.spawn("git", {
    hide = true,
    args = git_args or make_git_status_args(context.git_root),
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    if code ~= 0 then
      log.at.warn.format(
        "git status async process exited abnormally, code: %s, signal: %s",
        code,
        signal
      )
      return
    end

    stdin:shutdown()
    stdin:close()
    stdout:shutdown()
    stdout:close()
    stderr:shutdown()
    stderr:close()

    if #output_chunks == 0 then
      return
    end
    local output = output_chunks[1]
    if #output_chunks > 1 then
      output = table.concat(output_chunks, "")
    end

    ---@diagnostic disable-next-line: param-type-mismatch
    local status_iter = vim.gsplit(output, "\000", gsplit_plain)
    local parsing_task = co.create(M.parse_porcelain_output)
    log.assert(
      co.resume(parsing_task, context.git_root, status_iter, context.git_status, context.batch_size)
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

local status_jobs = {}

---@param path string path to run commands in
---@param base string git ref base
---@param opts neotree.Config.GitStatusAsync
M.status_async = function(path, base, opts)
  M.get_repository_root(path, function(git_root)
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
        -- do a fast scan first to get basic things in, then a full scan with ignore/untracked files
        async_git_status_job(
          ctx,
          make_git_status_args(git_root, "no", "no", { path }),
          function(fast_status)
            update_git_status(ctx, fast_status)
            async_git_status_job(ctx, nil, function(full_status)
              update_git_status(ctx, full_status)
            end)
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
    local direct_lookup = gs[i.path] or gs[i.path .. utils.path_separator]
    if direct_lookup == "!" then
      i.filtered_by = i.filtered_by or {}
      i.filtered_by.gitignored = true
    end
  end
end

local finalize = function(path, git_root)
  if utils.is_windows then
    git_root = utils.windowize_path(git_root)
  end

  log.trace("GIT ROOT for '", path, "' is '", git_root, "'")
end

---@param path string? Defaults to cwd
---@param callback fun(git_root: string?)?
---@return string?
M.get_repository_root = function(path, callback)
  path = path or log.assert(uv.cwd())

  log.trace("git.get_repository_root: cache miss for", path)
  local args = { "-C", path, "rev-parse", "--show-toplevel" }

  if type(callback) == "function" then
    ---@diagnostic disable-next-line: missing-fields
    Job:new({
      command = "git",
      args = { "-C", path, "rev-parse", "--show-toplevel" },
      enabled_recording = true,
      on_exit = function(self, code, _)
        if code ~= 0 then
          log.trace("GIT ROOT ERROR", self:stderr_result())
          callback(nil)
          return
        end
        local git_root = self:result()[1]

        finalize(path, git_root)
        callback(git_root)
      end,
    }):start()
    return
  end

  local ok, git_output = utils.execute_command({ "git", unpack(args) })
  if not ok then
    log.trace("GIT ROOT NOT FOUND", git_output)
    return nil
  end
  local git_root = git_output[1]

  finalize(path, git_root)
  return git_root
end

return M
