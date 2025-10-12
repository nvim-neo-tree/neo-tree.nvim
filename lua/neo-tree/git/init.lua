local utils = require("neo-tree.utils")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local Job = require("plenary.job")
local uv = vim.uv or vim.loop
local co = coroutine

local M = {}

---@type table<string, neotree.git.Status>
M.status_cache = setmetatable({}, {
  __mode = "v",
  __newindex = function(_, root_dir, status)
    require("neo-tree.sources.filesystem.lib.fs_watch").on_destroyed(root_dir, function()
      rawset(M.status_cache, root_dir, nil)
    end)
    rawset(M.status_cache, root_dir, status)
  end,
})

---@class (exact) neotree.git.Context : neotree.Config.GitStatusAsync
---@field git_status neotree.git.Status?
---@field git_root string
---@field lines_parsed integer

---@param git_root string
---@param status_iter fun():string?
---@param batch_size integer? This will use coroutine.yield if provided.
---@param skip_bubbling boolean?
---@return neotree.git.Status
local parse_porcelain_output = function(git_root, status_iter, batch_size, skip_bubbling)
  local git_root_dir = utils.normalize_path(git_root) .. utils.path_separator
  local prev_line = ""
  local num_in_batch = 0
  local git_status = {}
  if batch_size == 0 then
    batch_size = nil
  end
  local yield_if_batch_completed = function() end

  if batch_size then
    yield_if_batch_completed = function()
      num_in_batch = num_in_batch + 1
      if num_in_batch > batch_size then
        num_in_batch = 0
        coroutine.yield(git_status)
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
    yield_if_batch_completed()
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
    yield_if_batch_completed()
  end

  if not skip_bubbling then
    -- bubble up every status besides ignored
    local status_prio = { "U", "?", "M", "A" }

    for dir, status in pairs(git_status) do
      if status ~= "!" then
        local s = status:sub(1, 1)
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
              if s == c then
                git_status[parent] = c
              end
            end
          end
        end
      end
      yield_if_batch_completed()
    end
  end
  if prev_line:sub(1, 1) == "!" then
    git_status[git_root_dir .. prev_line:sub(3)] = "!"
    for line in status_iter do
      git_status[git_root_dir .. line:sub(3)] = "!"
    end
    yield_if_batch_completed()
  end

  M.status_cache[git_root] = git_status
  return git_status
end
---@alias neotree.git.Status table<string, string>

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
    "--no-optional-locks",
    "-C",
    git_root,
    "status",
    "--porcelain=v2",
    "--untracked-files=normal",
    "--ignored=traditional",
    "-z",
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
    local status_iter = vim.gsplit(status_result, "\001", { plain = true })
    local gs = parse_porcelain_output(git_root, status_iter, nil, skip_bubbling)

    context.git_status = gs
    vim.schedule(function()
      events.fire_event(events.GIT_STATUS_CHANGED, {
        git_root = context.git_root,
        git_status = context.git_status,
      })
    end)
    M.status_cache[git_root] = {}
  end

  return context.git_status, git_root
end

---@param path string path to run commands in
---@param base string git ref base
---@param opts neotree.Config.GitStatusAsync
M.status_async = function(path, base, opts)
  M.get_repository_root(path, function(git_root)
    if not git_root then
      log.trace("status_async: not a git folder:", path)
      return
    end
    ---@cast git_root -false

    log.trace("git.status.status_async called")

    local event_id = "git_status_" .. git_root
    ---@type neotree.git.Context
    local context = {
      git_root = git_root,
      git_status = {},
      lines = {},
      lines_parsed = 0,
      batch_size = opts.batch_size or 1000,
      batch_delay = opts.batch_delay or 10,
      max_lines = opts.max_lines or 100000,
    }

    utils.debounce(event_id, function()
      local stdin = log.assert(uv.new_pipe())
      local stdout = log.assert(uv.new_pipe())
      local stderr = log.assert(uv.new_pipe())

      local output_chunks = {}
      log.trace("spawning git")
      ---@diagnostic disable-next-line: missing-fields
      uv.spawn("git", {
        hide = true,
        args = {
          "--no-optional-locks",
          "-C",
          git_root,
          "status",
          "--porcelain=v2",
          "--untracked-files=normal",
          "--ignored=traditional",
          "-z",
        },
        stdio = { stdin, stdout, stderr },
      }, function(code, signal)
        if code ~= 0 then
          log.at.debug.format(
            "git status async process exited abnormally, code: %s, signal: %s",
            code,
            signal
          )
          return
        end
        local str = output_chunks[1]
        if #output_chunks > 1 then
          str = table.concat(output_chunks, "")
        end
        local status_iter = vim.gsplit(str, "\000", { plain = true })
        local parsing_task = co.create(parse_porcelain_output)
        local _, git_status =
          log.assert(co.resume(parsing_task, git_root, status_iter, context.batch_size))

        stdin:shutdown()
        stdout:shutdown()
        stderr:shutdown()

        local do_next_batch_later
        do_next_batch_later = function()
          if co.status(parsing_task) ~= "dead" then
            _, git_status = log.assert(co.resume(parsing_task))
            vim.defer_fn(do_next_batch_later, context.batch_delay)
            return
          end
          context.git_status = git_status
          M.status_cache[git_root] = git_status
          vim.schedule(function()
            events.fire_event(events.GIT_STATUS_CHANGED, {
              git_root = context.git_root,
              git_status = context.git_status,
            })
          end)
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
        if err then
          local errfmt = (err or "") .. "%s"
          log.at.error.format(errfmt, data)
        end
      end)
    end, 1000, utils.debounce_strategy.CALL_FIRST_AND_LAST, utils.debounce_action.START_ASYNC_JOB)
  end)
end

---@param state neotree.State
---@param items neotree.FileItem[]
M.mark_ignored = function(state, items)
  for _, i in ipairs(items) do
    repeat
      local path = i.path
      local git_root = M.get_repository_root(path)
      if not git_root then
        break
      end
      local status = M.status_cache[git_root] or M.status("HEAD", false, path)
      if not status then
        break
      end

      local direct_lookup = M.status_cache[git_root][path]
        or M.status_cache[git_root][path .. utils.path_separator]
      if direct_lookup then
        i.filtered_by = i.filtered_by or {}
        i.filtered_by.gitignored = true
      end
    until true
  end
end

---@type table<string, string|false>
do
  local git_rootdir_cache = setmetatable({}, { __mode = "kv" })
  local finalize = function(path, git_root)
    if utils.is_windows then
      git_root = utils.windowize_path(git_root)
    end

    log.trace("GIT ROOT for '", path, "' is '", git_root, "'")
    git_rootdir_cache[path] = git_root
    git_rootdir_cache[git_root] = git_root
  end

  ---@param path string? Defaults to cwd
  ---@param callback fun(git_root: string?)?
  ---@return string?
  M.get_repository_root = function(path, callback)
    path = path or log.assert(vim.uv.cwd())

    local cached_rootdir = git_rootdir_cache[path]
    if cached_rootdir ~= nil then
      log.trace("git.get_repository_root: cache hit for", path, "was", cached_rootdir)
      if callback then
        callback(cached_rootdir)
        return
      end
      return cached_rootdir
    end

    for parent in utils.path_parents(path, true) do
      local cached_parent_entry = git_rootdir_cache[parent]
      if cached_parent_entry ~= nil then
        log.trace(
          "git.get_repository_root: cache hit for parent of",
          path,
          ",",
          parent,
          "was",
          cached_parent_entry
        )
        git_rootdir_cache[path] = cached_parent_entry
        return cached_parent_entry
      end
    end

    log.trace("git.get_repository_root: cache miss for", path)
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
            git_rootdir_cache[path] = false
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
      git_rootdir_cache[path] = false
      return nil
    end
    local git_root = git_output[1]

    finalize(path, git_root)
    return git_root
  end
end
return M
