local utils = require("neo-tree.utils")

local M = {}

---@param path string
---@return string path_with_no_trailing_slash
local remove_trailing_unix_slash = function(path)
  return path:sub(-1, -1) == "/" and path:sub(1, -2) or path
end

local COMMENT_BYTE = ("#"):byte()
local TYPE_ONE_BYTE = ("1"):byte()
local TYPE_TWO_BYTE = ("2"):byte()
local UNMERGED_BYTE = ("u"):byte()
local UNTRACKED_BYTE = ("?"):byte()
local IGNORED_BYTE = ("!"):byte()
local parent_cache = setmetatable({}, { __mode = "kv" })

---@param context neotree.git.JobContext
---@vararg any
---@return boolean
local increment_batch_or_yield = function(context, ...)
  context.lines_parsed = context.lines_parsed + 1
  if context.lines_parsed >= context.max_lines then
    return false
  end
  context.num_in_batch = context.num_in_batch + 1
  if context.num_in_batch >= context.batch_size then
    context.num_in_batch = 0
    if coroutine.running() then
      coroutine.yield(...)
    end
  end
  return true
end

---@class neotree.git.parser.BatchOpts
---@field batch_size integer
---@field max_lines integer

local STATUS_PRIORITY_STRING = "U?MADTRC."
---@param bubble_info string[][]
---@param paths string[]
---@param worktree_root string
---@return neotree.git.Status parent_statuses
local function create_parent_status_map(bubble_info, paths, worktree_root)
  local parent_statuses = {}

  local worktree_root_len = #worktree_root
  for i = 1, #STATUS_PRIORITY_STRING do
    local status = { STATUS_PRIORITY_STRING:sub(i, i) }
    local list = bubble_info[i]
    if not list then
      break
    end
    -- bubble them up
    for _, index in ipairs(list) do
      local path = paths[index]
      local parent
      repeat
        local cached = parent_cache[path]
        if cached then
          parent = cached
        else
          parent = utils.split_path(path)
          if not parent then
            break
          end
          parent_cache[path] = parent
        end

        if worktree_root_len >= #parent then
          break
        end
        if parent_statuses[parent] ~= nil then
          break
        end

        parent_statuses[parent] = status
        path = parent
      until false
    end
  end
  return parent_statuses
end

---@param porcelain_version 1|2
---@param worktree_root string The git status table to override, if any.
---@param status_iter fun():string? An iterator that returns each line of the status.
---@param skip_bubbling boolean?
---@param context neotree.git.JobContext?
---@return neotree.git.Status status
M.parse_status_porcelain = function(
  porcelain_version,
  worktree_root,
  status_iter,
  skip_bubbling,
  context
)
  local git_root_dir = utils.normalize_path(worktree_root)
  if not vim.endswith(git_root_dir, utils.path_separator) then
    git_root_dir = git_root_dir .. utils.path_separator
  end

  local git_status = context and context.git_status or {}

  local line = status_iter()

  ---@type string[]
  local statuses = {}
  ---@type string[]
  local paths = {}

  ---@type integer[]
  local unmerged = {}

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
      if #XY == 0 or XY == "??" or XY == "!!" then
        break
      end

      if XY ~= "# " then
        local X = XY:sub(1, 1)
        local Y = XY:sub(2, 2)
        if M.status_code_is_conflict(X, Y) then
          unmerged[#unmerged + 1] = #paths + 1
        elseif X == "R" or Y == "R" or X == "C" or Y == "C" then
          status_iter() -- consume original path
        end

        local path = line:sub(4)
        local abspath = git_root_dir .. path
        paths[#paths + 1] = abspath
        statuses[#statuses + 1] = XY:gsub(" ", ".")
      end
      line = status_iter()
      if context then
        if not increment_batch_or_yield(context, git_status) then
          break
        end
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
      local abspath, XY
      if line_type_byte == COMMENT_BYTE then
        -- continue for now
      elseif line_type_byte == TYPE_ONE_BYTE then
        XY = line:sub(3, 4)
        -- local submodule_state = line:sub(6, 9)
        -- local mH = line:sub(11, 16)
        -- local mI = line:sub(18, 23)
        -- local mW = line:sub(25, 30)
        -- local hH = line:sub(32, 71)
        -- local hI = line:sub(73, 112)
        local path = line:sub(114)
        abspath = git_root_dir .. path
      elseif line_type_byte == TYPE_TWO_BYTE then
        XY = line:sub(3, 4)
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
        abspath = git_root_dir .. path
        -- ignore the original path
        status_iter()
      elseif line_type_byte == UNMERGED_BYTE then
        XY = line:sub(3, 4)
        -- local submodule_state = line:sub(6, 9)
        -- local m1 = line:sub(11, 16)
        -- local m2 = line:sub(18, 23)
        -- local m3 = line:sub(25, 30)
        -- local mW = line:sub(32, 37)
        -- local h1 = line:sub(39, 78)
        -- local h2 = line:sub(80, 119)
        -- local h3 = line:sub(121, 160)
        local path = line:sub(162)
        abspath = git_root_dir .. path

        unmerged[#unmerged + 1] = #paths + 1
      else
        -- either untracked or ignored
        break
      end
      paths[#paths + 1] = abspath
      statuses[#statuses + 1] = XY
      if context then
        if not increment_batch_or_yield(context, git_status) then
          break
        end
      end
      line = status_iter()
    end
  end

  -- -------------------------------------------------
  -- ?           ?    untracked
  -- !           !    ignored
  -- -------------------------------------------------
  -- in v1, the lines are ?? and !! respectively so we need to adjust the offset accordingly
  local path_start = porcelain_version == 2 and 3 or 4

  while line and line:byte(1, 1) == UNTRACKED_BYTE do
    local abspath = git_root_dir .. remove_trailing_unix_slash(line:sub(path_start))
    paths[#paths + 1] = abspath
    statuses[#statuses + 1] = "?"
    line = status_iter()
    if context then
      if not increment_batch_or_yield(context, git_status) then
        break
      end
    end
  end

  for i, p in ipairs(paths) do
    if utils.is_windows then
      p = utils.windowize_path(p)
    end
    git_status[p] = statuses[i]
  end

  if not skip_bubbling then
    ---@type integer[]
    local untracked = {}
    ---@type integer[]
    local modified = {}
    ---@type integer[]
    local added = {}
    ---@type integer[]
    local deleted = {}
    ---@type integer[]
    local typechanged = {}
    ---@type integer[]
    local renamed = {}
    ---@type integer[]
    local copied = {}

    local prio_matrix = {
      unmerged,
      untracked,
      modified,
      added,
      deleted,
      typechanged,
      renamed,
      copied,
      {},
    }
    for i, s in ipairs(statuses) do
      -- simplify statuses to the highest priority ones
      local a, b = string.byte(s, 1, 2)
      if a then
        local a_char = string.char(a)
        local a_prio = assert(STATUS_PRIORITY_STRING:find(a_char, 1, true))
        if b then
          local b_char = string.char(b)
          local b_prio = STATUS_PRIORITY_STRING:find(b_char, 1, true)
          local list = prio_matrix[math.min(a_prio, b_prio)]
          if list then
            list[#list + 1] = i
          end
        else
          local list = prio_matrix[a_prio]
          if list then
            list[#list + 1] = i
          end
        end
      end
    end
    local parent_statuses = create_parent_status_map({
      unmerged,
      untracked,
      modified,
      added,
      deleted,
      typechanged,
      renamed,
      copied,
    }, paths, worktree_root)
    for parent, status in pairs(parent_statuses) do
      git_status[parent] = status
    end
  end

  while line and line:byte(1, 1) == IGNORED_BYTE do
    local abspath = git_root_dir .. remove_trailing_unix_slash(line:sub(path_start))
    if utils.is_windows then
      abspath = utils.windowize_path(abspath)
    end
    git_status[abspath] = "!"
    line = status_iter()

    if context then
      if not increment_batch_or_yield(context, git_status) then
        break
      end
    end
  end

  return git_status
end

---@param x string
---@param y string?
M.status_code_is_conflict = function(x, y)
  local both_deleted_or_added = x == y and (x == "A" or x == "D")
  return both_deleted_or_added or (x == "U" or y == "U")
end

---@param worktree_root string The git status table to override, if any.
---@param filepaths_iter fun():string? An iterator that returns each line of the status.
---@param context neotree.git.JobContext?
---@return string[]
M.parse_ls_files_output = function(worktree_root, filepaths_iter, context)
  local worktree_root_dir = worktree_root
  if not vim.endswith(worktree_root_dir, utils.path_separator) then
    worktree_root_dir = worktree_root_dir .. utils.path_separator
  end

  if context then
    assert(coroutine.running(), "async_opts shouldn't be provided if not in non-main coroutine")
  end

  local paths = {}
  for relpath in filepaths_iter do
    if #relpath > 0 then
      relpath = remove_trailing_unix_slash(relpath)
      if utils.is_windows then
        relpath = utils.windowize_path(relpath)
      end

      local abspath = worktree_root_dir .. relpath
      paths[#paths + 1] = abspath

      if context then
        if not increment_batch_or_yield(context) then
          break
        end
      end
    end
  end
  return paths
end

---@param worktree_root string The git status table to override, if any.
---@param diff_name_status_iter fun():string? An iterator that returns each line of the status.
---@param skip_bubbling boolean?
---@param context neotree.git.JobContext?
---@return string[]
M.parse_diff_name_status_output = function(
  worktree_root,
  skip_bubbling,
  diff_name_status_iter,
  context
)
  local worktree_root_dir = worktree_root
  if not vim.endswith(worktree_root_dir, utils.path_separator) then
    worktree_root_dir = worktree_root_dir .. utils.path_separator
  end

  if context then
    assert(coroutine.running(), "context shouldn't be provided if not in non-main coroutine")
  end

  local diff_status = {}
  -- output order is:
  -- M
  -- .github/workflows/.luarc-5.1.json
  -- M
  -- .github/workflows/.luarc-luajit-master.json
  -- M
  -- .github/workflows/ci.yml
  -- A
  -- .github/workflows/emmylua-check.yml
  -- M
  -- .github/workflows/luals-check.ymL
  ---@type string[]
  local paths = {}
  ---@type string[]
  local statuses = {}
  for status_code in diff_name_status_iter do
    status_code = status_code .. "."
    statuses[#statuses + 1] = status_code
    local path = diff_name_status_iter()
    if #status_code > 0 and path then
      path = remove_trailing_unix_slash(path)
      if utils.is_windows then
        path = utils.windowize_path(path)
      end

      local abspath = worktree_root_dir .. path
      paths[#paths + 1] = abspath
      diff_status[abspath] = status_code
    end
    if context then
      if not increment_batch_or_yield(context, diff_status) then
        break
      end
    end
  end

  if not skip_bubbling then
    ---@type integer[]
    local unmerged = {}
    ---@type integer[]
    local untracked = {}
    ---@type integer[]
    local modified = {}
    ---@type integer[]
    local added = {}
    ---@type integer[]
    local deleted = {}
    ---@type integer[]
    local typechanged = {}
    ---@type integer[]
    local renamed = {}
    ---@type integer[]
    local copied = {}

    local prio_matrix = {
      unmerged,
      untracked,
      modified,
      added,
      deleted,
      typechanged,
      renamed,
      copied,
      {},
    }
    for i, s in ipairs(statuses) do
      -- simplify statuses to the highest priority ones
      local a, b = string.byte(s, 1, 2)
      if a then
        local a_char = string.char(a)
        local a_prio = assert(STATUS_PRIORITY_STRING:find(a_char, 1, true))
        if b then
          local b_char = string.char(b)
          local b_prio = STATUS_PRIORITY_STRING:find(b_char, 1, true)
          local list = prio_matrix[math.min(a_prio, b_prio)]
          if list then
            list[#list + 1] = i
          end
        else
          local list = prio_matrix[a_prio]
          if list then
            list[#list + 1] = i
          end
        end
      end
    end

    local parent_statuses = create_parent_status_map({
      unmerged,
      untracked,
      modified,
      added,
      deleted,
      typechanged,
      renamed,
      copied,
    }, paths, worktree_root)
    for parent, status in pairs(parent_statuses) do
      diff_status[parent] = status
    end
  end
  return diff_status
end

return M
