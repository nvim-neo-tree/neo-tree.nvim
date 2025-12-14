local utils = require("neo-tree.utils")
local can_create_presized_table, new_table = pcall(require, "table.new")

local M = {}
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
local parent_cache = setmetatable({}, { __mode = "kv" })

---Exposed only for testing, parses a porcelain version into
---@param porcelain_version 1|2
---@param status_iter fun():string? An iterator that returns each line of the status.
---@param git_status neotree.git.Status? The git status table to override, if any.
---@param batch_size integer? This will use coroutine.yield if non-nil and > 0.
---@param skip_bubbling boolean?
---@return neotree.git.Status status
---@return string[] ignored
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
        statuses[#statuses + 1] = XY:gsub(" ", ".")
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

  -- -------------------------------------------------
  -- ?           ?    untracked
  -- !           !    ignored
  -- -------------------------------------------------
  -- in v1, the lines are ?? and !! respectively so we need to adjust the offset accordingly
  local path_start = porcelain_version == 2 and 3 or 4

  while line and line:byte(1, 1) == UNTRACKED_BYTE do
    local abspath = git_root_dir .. trim_trailing_slash(line:sub(path_start))
    if utils.is_windows then
      abspath = utils.windowize_path(abspath)
    end
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
    local flattened_len = #statuses
    for i, s in ipairs(statuses) do
      -- simplify statuses to the highest priority ones
      if s:find("U", 1, true) then
        statuses[i] = "U"
        conflicts[#conflicts + 1] = i
      elseif s:find("?", 1, true) then
        statuses[i] = "?"
        untracked[#untracked + 1] = i
      elseif s:find("M", 1, true) then
        statuses[i] = "M"
        modified[#modified + 1] = i
      elseif s:find("A", 1, true) then
        statuses[i] = "A"
        added[#added + 1] = i
      elseif s:find("D", 1, true) then
        statuses[i] = "D"
        deleted[#deleted + 1] = i
      elseif s:find("T", 1, true) then
        statuses[i] = "T"
        typechanged[#typechanged + 1] = i
      elseif s:find("R", 1, true) then
        statuses[i] = "R"
        renamed[#renamed + 1] = i
      elseif s:find("C", 1, true) then
        statuses[i] = "C"
        copied[#copied + 1] = i
      else
        flattened_len = flattened_len - 1
      end
    end
    local bubbleable_statuses_by_prio = can_create_presized_table and new_table(flattened_len, 0)
      or {}

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
      require("neo-tree.utils._compat").luajit.table_move(
        list,
        1,
        #list,
        #bubbleable_statuses_by_prio + 1,
        bubbleable_statuses_by_prio
      )
    end

    -- bubble them up
    local parent_statuses = {}
    do
      for _, i in ipairs(bubbleable_statuses_by_prio) do
        local path = paths[i]
        local status = statuses[i]
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

  local ignored = {}
  while line and line:byte(1, 1) == IGNORED_BYTE do
    local abspath = git_root_dir .. trim_trailing_slash(line:sub(path_start))
    if utils.is_windows then
      abspath = utils.windowize_path(abspath)
    end
    git_status[abspath] = "!"
    ignored[#ignored + 1] = abspath
    line = status_iter()

    if batch_size then
      yield_if_batch_completed()
    end
  end

  return git_status, ignored
end

return M
