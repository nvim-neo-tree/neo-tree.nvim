local utils = require("neo-tree.utils")
local events = require("neo-tree.events")
local Job = require("plenary.job")
local log = require("neo-tree.log")
local git_utils = require("neo-tree.git.utils")

local M = {}

local function get_simple_git_status_code(status)
  -- Prioritze M then A over all others
  if status:match("U") or status == "AA" or status == "DD" then
    return "U"
  elseif status:match("M") then
    return "M"
  elseif status:match("[ACR]") then
    return "A"
  elseif status:match("!$") then
    return "!"
  elseif status:match("?$") then
    return "?"
  else
    local len = #status
    while len > 0 do
      local char = status:sub(len, len)
      if char ~= " " then
        return char
      end
      len = len - 1
    end
    return status
  end
end

local function get_priority_git_status_code(status, other_status)
  if not status then
    return other_status
  elseif not other_status then
    return status
  elseif status == "U" or other_status == "U" then
    return "U"
  elseif status == "?" or other_status == "?" then
    return "?"
  elseif status == "M" or other_status == "M" then
    return "M"
  elseif status == "A" or other_status == "A" then
    return "A"
  else
    return status
  end
end

---@class (exact) neotree.git.Context
---@field git_status neotree.git.Status
---@field git_root string
---@field exclude_directories boolean
---@field lines_parsed integer

---@alias neotree.git.Status table<string, string>

---@param context neotree.git.Context
local parse_git_status_line = function(context, line)
  context.lines_parsed = context.lines_parsed + 1
  if type(line) ~= "string" then
    return
  end
  if #line < 3 then
    return
  end
  local git_root = context.git_root
  local git_status = context.git_status
  local exclude_directories = context.exclude_directories

  local line_parts = vim.split(line, "	")
  if #line_parts < 2 then
    return
  end
  local status = line_parts[1]
  local relative_path = line_parts[2]

  -- rename output is `R000 from/filename to/filename`
  if status:match("^R") then
    relative_path = line_parts[3]
  end

  -- remove any " due to whitespace or utf-8 in the path
  relative_path = relative_path:gsub('^"', ""):gsub('"$', "")
  -- convert octal encoded lines to utf-8
  relative_path = git_utils.octal_to_utf8(relative_path)

  if utils.is_windows == true then
    relative_path = utils.windowize_path(relative_path)
  end
  local absolute_path = utils.path_join(git_root, relative_path)
  -- merge status result if there are results from multiple passes
  local existing_status = git_status[absolute_path]
  if existing_status then
    local merged = ""
    local i = 0
    while i < 2 do
      i = i + 1
      local existing_char = #existing_status >= i and existing_status:sub(i, i) or ""
      local new_char = #status >= i and status:sub(i, i) or ""
      local merged_char = get_priority_git_status_code(existing_char, new_char)
      merged = merged .. merged_char
    end
    status = merged
  end
  git_status[absolute_path] = status

  if not exclude_directories then
    -- Now bubble this status up to the parent directories
    local parts = utils.split(absolute_path, utils.path_separator)
    table.remove(parts) -- pop the last part so we don't override the file's status
    utils.reduce(parts, "", function(acc, part)
      local path = acc .. utils.path_separator .. part
      if utils.is_windows == true then
        path = path:gsub("^" .. utils.path_separator, "")
      end
      local path_status = git_status[path]
      local file_status = get_simple_git_status_code(status)
      git_status[path] = get_priority_git_status_code(path_status, file_status)
      return path
    end)
  end
end

---Parse "git status" output for the current working directory.
---@param base string git ref base
---@param exclude_directories boolean Whether to skip bubling up status to directories
---@param path string Path to run the git status command in, defaults to cwd.
---@return neotree.git.Status, string? git_status the neotree.Git.Status of the given root
M.status = function(base, exclude_directories, path)
  local git_root = git_utils.get_repository_root(path)
  if not utils.truthy(git_root) then
    return {}
  end
  local git_root_dir = git_root .. utils.path_separator

  local s1 = vim.uv.hrtime()
  local status_cmd = {
    "git",
    "-c",
    "status.relativePaths=true",
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
  if not status_ok then
    return {}
  end

  local m1 = vim.uv.hrtime()
  ---@type table<string, string>
  local gs = {}
  -- system() replaces \000 with \001
  local status_iter = vim.gsplit(status_result, "\001", { plain = true })
  local prev_line = ""
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
      local pathname = line:sub(114)
      gs[git_root_dir .. pathname] = XY
    elseif t == "2" then
      -- local XY = line:sub(3, 4)
      -- local submodule_state = line:sub(6, 9)
      -- local mH = line:sub(11, 16)
      -- local mI = line:sub(18, 23)
      -- local mW = line:sub(25, 30)
      -- local hH = line:sub(32, 71)
      -- local hI = line:sub(73, 112)
      local rest = line:sub(114)
      local score_and_pathname = vim.split(rest, " ", { plain = true })
      -- iterate over the original path
      gs[git_root_dir .. score_and_pathname[2]] = score_and_pathname[1]
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
      local pathname = line:sub(162)
      gs[git_root_dir .. pathname] = XY
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
    -- -------------------------------------------------
    -- ?           ?    untracked
    -- !           !    ignored
    -- -------------------------------------------------
  end

  if prev_line:sub(1, 1) == "?" then
    gs[git_root_dir .. prev_line:sub(3)] = "?"
    for line in status_iter do
      if line:sub(1, 1) ~= "?" then
        prev_line = line
        break
      end
      gs[git_root_dir .. line:sub(3)] = "?"
    end
  end

  if prev_line:sub(1, 1) == "!" then
    gs[git_root_dir .. prev_line:sub(3)] = "!"
    for line in status_iter do
      gs[git_root_dir .. line:sub(3)] = "!"
    end
  end

  -- bubble up every status
  for dir, status in pairs(gs) do
    for parent in utils.path_parents(dir) do
      local parent_status = gs[parent]
      if not parent_status then
        gs[parent] = status
      else
        local better_status
        if status == "?" then
        if better_status == parent_status then
          break -- stop bubbling
        end
        gs[parent] = better_status
      end
    end
  end
  local e1 = vim.uv.hrtime()

  local s2 = vim.uv.hrtime()
  local staged_cmd = { "git", "-C", git_root, "diff", "--staged", "--name-status", base, "--" }
  local staged_ok, staged_result = utils.execute_command(staged_cmd)
  if not staged_ok then
    return {}
  end
  local unstaged_cmd = { "git", "-C", git_root, "diff", "--name-status" }
  local unstaged_ok, unstaged_result = utils.execute_command(unstaged_cmd)
  if not unstaged_ok then
    return {}
  end
  local untracked_cmd = { "git", "-C", git_root, "ls-files", "--exclude-standard", "--others" }
  local untracked_ok, untracked_result = utils.execute_command(untracked_cmd)
  if not untracked_ok then
    return {}
  end
  local m2 = vim.uv.hrtime()

  local context = {
    git_root = git_root,
    git_status = {},
    exclude_directories = exclude_directories,
    lines_parsed = 0,
  }

  for _, line in ipairs(staged_result) do
    parse_git_status_line(context, line)
  end
  for _, line in ipairs(unstaged_result) do
    if line then
      line = " " .. line
    end
    parse_git_status_line(context, line)
  end
  for _, line in ipairs(untracked_result) do
    if line then
      line = "?	" .. line
    end
    parse_git_status_line(context, line)
  end
  local e2 = vim.uv.hrtime()
  print("entire:", e1 - s1)
  print("cmd:", m1 - s1)
  print("parse:", e1 - m1)
  print(vim.inspect(gs))

  print("entire:", e2 - s2)
  print("cmd:", m2 - s2)
  print("parse:", e2 - m2)
  print(vim.inspect(context.git_status))

  return context.git_status, git_root
end

local function parse_lines_batch(context, job_complete_callback)
  local i, batch_size = 0, context.batch_size

  if context.lines_total == nil then
    -- first time through, get the total number of lines
    context.lines_total = math.min(context.max_lines, #context.lines)
    context.lines_parsed = 0
    if context.lines_total == 0 then
      if type(job_complete_callback) == "function" then
        job_complete_callback()
      end
      return
    end
  end
  batch_size = math.min(context.batch_size, context.lines_total - context.lines_parsed)

  while i < batch_size do
    i = i + 1
    parse_git_status_line(context, context.lines[context.lines_parsed + 1])
  end

  if context.lines_parsed >= context.lines_total then
    if type(job_complete_callback) == "function" then
      job_complete_callback()
    end
  else
    -- add small delay so other work can happen
    vim.defer_fn(function()
      parse_lines_batch(context, job_complete_callback)
    end, context.batch_delay)
  end
end

M.status_async = function(path, base, opts)
  git_utils.get_repository_root(path, function(git_root)
    if utils.truthy(git_root) then
      log.trace("git.status.status_async called")
    else
      log.trace("status_async: not a git folder:", path)
      return false
    end

    local event_id = "git_status_" .. git_root
    ---@type neotree.git.Context
    local context = {
      git_root = git_root,
      git_status = {},
      exclude_directories = false,
      lines = {},
      lines_parsed = 0,
      batch_size = opts.batch_size or 1000,
      batch_delay = opts.batch_delay or 10,
      max_lines = opts.max_lines or 100000,
    }

    local should_process = function(err, line, job, err_msg)
      if vim.v.dying > 0 or vim.v.exiting ~= vim.NIL then
        job:shutdown()
        return false
      end
      if err and err > 0 then
        log.error(err_msg, err, line)
        return false
      end
      return true
    end

    local job_complete_callback = function()
      vim.schedule(function()
        events.fire_event(events.GIT_STATUS_CHANGED, {
          git_root = context.git_root,
          git_status = context.git_status,
        })
      end)
    end

    local parse_lines = vim.schedule_wrap(function()
      parse_lines_batch(context, job_complete_callback)
    end)

    utils.debounce(event_id, function()
      ---@diagnostic disable-next-line: missing-fields
      local staged_job = Job:new({
        command = "git",
        args = { "-C", git_root, "diff", "--staged", "--name-status", base, "--" },
        enable_recording = false,
        maximium_results = context.max_lines,
        on_stdout = function(err, line, job)
          table.insert(context.lines, line)
        end,
        on_stderr = function(err, line)
          if err and err > 0 then
            log.error("status_async staged error: ", err, line)
          end
        end,
      })

      ---@diagnostic disable-next-line: missing-fields
      local unstaged_job = Job:new({
        command = "git",
        args = { "-C", git_root, "diff", "--name-status" },
        enable_recording = false,
        maximium_results = context.max_lines,
        on_stdout = function(err, line, job)
          if should_process(err, line, job, "status_async unstaged error:") then
            if line then
              line = " " .. line
            end
            table.insert(context.lines, line)
          end
        end,
        on_stderr = function(err, line)
          if err and err > 0 then
            log.error("status_async unstaged error: ", err, line)
          end
        end,
      })

      ---@diagnostic disable-next-line: missing-fields
      local untracked_job = Job:new({
        command = "git",
        args = { "-C", git_root, "ls-files", "--exclude-standard", "--others" },
        enable_recording = false,
        maximium_results = context.max_lines,
        on_stdout = function(err, line, job)
          if should_process(err, line, job, "status_async untracked error:") then
            if line then
              line = "?	" .. line
            end
            table.insert(context.lines, line)
          end
        end,
        on_stderr = function(err, line)
          if err and err > 0 then
            log.error("status_async untracked error: ", err, line)
          end
        end,
      })

      ---@diagnostic disable-next-line: missing-fields
      Job:new({
        command = "git",
        args = {
          "-C",
          git_root,
          "config",
          "--get",
          "status.showUntrackedFiles",
        },
        enabled_recording = true,
        on_exit = function(self, _, _)
          local result = self:result()
          log.debug("git status.showUntrackedFiles =", result[1])
          if result[1] == "no" then
            unstaged_job:after(parse_lines)
            Job.chain(staged_job, unstaged_job)
          else
            untracked_job:after(parse_lines)
            Job.chain(staged_job, unstaged_job, untracked_job)
          end
        end,
      }):start()
    end, 1000, utils.debounce_strategy.CALL_FIRST_AND_LAST, utils.debounce_action.START_ASYNC_JOB)

    return true
  end)
end

return M
