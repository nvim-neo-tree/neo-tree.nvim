local vim = vim
local log = require("neo-tree.log")
local Job = require("plenary.job")
local utils = require("neo-tree.utils")

local M = {}
local fd_supports_max_results = nil
local unpack = unpack or table.unpack

local test_for_max_results = function(cmd)
  if fd_supports_max_results == nil then
    if cmd == "fd" or cmd == "fdfind" then
      --test if it supports the max-results option
      local test = vim.fn.system(cmd .. " this_is_only_a_test --max-depth=1 --max-results=1")
      if test:match("^error:") then
        fd_supports_max_results = false
        log.debug(cmd, "does NOT support max-results")
      else
        fd_supports_max_results = true
        log.debug(cmd, "supports max-results")
      end
    end
  end
end

local get_find_command = function(state)
  if state.find_command then
    test_for_max_results(state.find_command)
    return state.find_command
  end

  if 1 == vim.fn.executable("fdfind") then
    state.find_command = "fdfind"
  elseif 1 == vim.fn.executable("fd") then
    state.find_command = "fd"
  elseif 1 == vim.fn.executable("find") and vim.fn.has("win32") == 0 then
    state.find_command = "find"
  elseif 1 == vim.fn.executable("where") then
    state.find_command = "where"
  end

  test_for_max_results(state.find_command)
  return state.find_command
end

---@class FileTypes
---@field file boolean
---@field directory boolean
---@field symlink boolean
---@field socket boolean
---@field pipe boolean
---@field executable boolean
---@field empty boolean
---@field block boolean Only for `find`
---@field character boolean Only for `find`

---filter_files_external
-- Spawns a filter command based on `cmd`
---@param cmd string Command to execute. Use `get_find_command` most times.
---@param path string Base directory to start the search.
---@param glob string | nil If not nil, do glob search. Take precedence on `regex`
---@param regex string | nil If not nil, do regex search if command supports. if glob ~= nil, ignored
---@param full_path boolean If true, search agaist the absolute path
---@param types FileTypes | nil Return only true filetypes. If nil, all are returned.
---@param ignore { dotfiles: boolean?, gitignore: boolean? } If true, ignored from result. Default: false
---@param limit? integer | nil Maximim number of results. nil will return everything.
---@param find_args? string[] | table<string, string[]> Any additional options passed to command if any.
---@param on_insert? fun(err: string, line: string): any Executed for each line of stdout and stderr.
---@param on_exit? fun(return_val: table): any Executed at the end.
M.filter_files_external = function(cmd, path, glob, regex, full_path, types, ignore, limit, find_args, on_insert, on_exit)
  if glob ~= nil and regex ~= nil then
    local log_msg = string.format([[glob: %s, regex: %s]], glob, regex)
    log.warning("both glob and regex are set. glob will take precedence. " .. log_msg)
  end
  ignore = ignore or {}
  types = types or {}
  limit = limit or math.huge -- math.huge == no limit
  local file_type_map = {
    file = "f",
    directory = "d",
    symlink = "l",
    socket = "s",
    pipe = "p",
    executable = "x", -- only for `fd`
    empty = "e", -- only for `fd`
    block = "b", -- only for `find`
    character = "c", -- only for `find`
  }

  local args = {}
  local function append(...)
    for _, v in pairs({ ... }) do
      if v ~= nil then
        args[#args + 1] = v
      end
    end
  end

  if cmd == "fd" or cmd == "fdfind" then
    if not ignore.dotfiles then
      append("--hidden")
    end
    if not ignore.gitignore then
      append("--no-ignore")
    end
    append("--color", "never")
    if fd_supports_max_results and 0 < limit and limit < math.huge then
      append("--max-results", limit)
    end
    for k, v in pairs(types) do
      if v and file_type_map[k] ~= nil then
        append("--type", k)
      end
    end
    if full_path then
      append("--full-path")
      if glob ~= nil then
        local words = utils.split(glob, " ")
        regex = ".*" .. table.concat(words, ".*") .. ".*"
        glob = nil
      end
    end
    if glob ~= nil then
      append("--glob")
    end
    append("--", glob or regex or "")
    append(path)
  elseif cmd == "find" then
    append(path)
    local file_types = {}
    for k, v in pairs(types) do
      if v and file_type_map[k] ~= nil then
        file_types[#file_types + 1] = file_type_map[k]
      end
    end
    if #file_types > 0 then
      append("-type", table.concat(file_types, ","))
    end
    if types.empty then
      append("-empty")
    end
    if types.executable then
      append("-executable")
    end
    if not ignore.dotfiles then
      append("-not", "-path", "*/.*")
    end
    if glob ~= nil and not full_path then
      append("-iname", glob)
    elseif glob ~= nil and full_path then
      local words = utils.split(glob, " ")
      regex = ".*" .. table.concat(words, ".*") .. ".*"
      append("-regextype", "sed", "-regex", regex)
    elseif regex ~= nil then
      append("-regextype", "sed", "-regex", regex)
    end
  elseif cmd == "fzf" then
    -- This does not work yet, there's some kind of issue with how fzf uses stdout
    error("fzf is not a supported find_command")
    append("--no-sort", "--no-expect", "--filter", glob or regex) -- using the raw term without glob patterns
  elseif cmd == "where" then
    append("/r", path, glob or regex)
  else
    return { "No search command found!" }
  end

  if find_args then
    if type(find_args) == "string" then
      append(find_args)
    elseif type(find_args) == "table" then
      if find_args[1] then
        append(unpack(find_args))
      elseif find_args[cmd] then
        append(unpack(find_args[cmd])) ---@diagnostic disable-line
      end
    elseif type(find_args) == "function" then
      args = find_args(cmd, path, glob, args)
    end
  end

  if fd_supports_max_results then
    limit = math.huge -- `fd` manages limit on its own
  end
  local item_count = 0
  Job:new({
    command = cmd,
    cwd = path,
    args = args,
    enable_recording = false,
    on_stdout = function(err, line)
      if item_count < limit and on_insert then
        on_insert(err, line)
        item_count = item_count + 1
      end
    end,
    on_stderr = function(err, line)
      if item_count < limit and on_insert then
        on_insert(err or line, line)
        item_count = item_count + 1
      end
    end,
    on_exit = function(_, return_val)
      if on_exit then
        on_exit(return_val)
      end
    end,
  }):start()
end

local function fzy_sort_get_total_score(terms, path)
  local fzy = require("neo-tree.sources.filesystem.lib.filter_fzy")
  local total_score = 0
  for _, term in ipairs(terms) do -- spaces in `opts.term` are treated as `and`
    local score = fzy.score(term, path)
    if score == fzy.get_score_min() then -- if any not found, end searching
      return 0
    end
    total_score = total_score + score
  end
  return total_score
end

local function modify_parent_scores(result_scores, path, score)
  local parent, _ = utils.split_path(path)
  while parent ~= nil do -- back propagate the score to its ancesters
    if score > (result_scores[parent] or 0) then
      result_scores[parent] = score
      parent, _ = utils.split_path(parent)
    else
      break
    end
  end
end

M.fzy_sort_files = function(opts, state)
  state = state or {}
  local filters = opts.filtered_items
  local limit = opts.limit or 100
  local full_path_words = opts.find_by_full_path_words
  local fuzzy_finder_mode = opts.fuzzy_finder_mode
  local pwd = opts.path
  if pwd:sub(-1) ~= "/" then
    pwd = pwd .. "/"
  end
  local pwd_length = #pwd
  local terms = {}
  for term in string.gmatch(opts.term, "[^%s]+") do -- space split opts.term
    terms[#terms + 1] = term
  end
  local result_counter = 0

  if state.fzy_sort_file_list_cache ~= nil and #state.fzy_sort_file_list_cache > 0 then
    -- list of files are already cached
    for _, relative_path in ipairs(state.fzy_sort_file_list_cache) do
      -- if full_path_words, contents of state.fzy_sort_file_list_cache is absolute path
      local path = full_path_words and relative_path or pwd .. relative_path
      local score = fzy_sort_get_total_score(terms, relative_path)
      if score > 0 then
        state.fzy_sort_result_scores[path] = score
        result_counter = result_counter + 1
        modify_parent_scores(state.fzy_sort_result_scores, path, score)
        opts.on_insert(nil, path)
        if result_counter >= limit then
          break
        end
      end
    end

    if opts.on_exit then
      opts.on_exit(0)
    end
  else
    -- fetch file list for the first time and calculate scores along the way
    state.fzy_sort_file_list_cache = {}
    local index = 1
    local cached_everything = true
    state.fzy_sort_result_scores = { foo = 0, baz = 0 }
    local function on_insert(err, path)
      if not err then
        if result_counter >= limit then
          cached_everything = false
          return
        end
        local relative_path = path
        if not full_path_words and #path > pwd_length and path:sub(1, pwd_length) == pwd then
          relative_path = "./" .. path:sub(pwd_length + 1)
        end
        state.fzy_sort_file_list_cache[index] = relative_path
        index = index + 1
        state.fzy_sort_result_scores[path] = 0
        local score = fzy_sort_get_total_score(terms, relative_path)
        if score > 0 then
          state.fzy_sort_result_scores[path] = score
          result_counter = result_counter + 1
          modify_parent_scores(state.fzy_sort_result_scores, path, score)
          opts.on_insert(nil, path)
        end
      end
    end

    local function on_exit(_)
      log.debug(string.format([[fzy_sort_files: cached_everything: %s, len: %s]], cached_everything,
        #state.fzy_sort_file_list_cache))
      if not cached_everything then
        state.fzy_sort_file_list_cache = {}
      end
      opts.on_exit(0)
    end

    M.filter_files_external(get_find_command(state), pwd, nil, nil, true,
      { directory = fuzzy_finder_mode == "directory", file = fuzzy_finder_mode ~= "directory" },
      { dotfiles = not filters.visible and filters.hide_dotfiles,
        gitignore = not filters.visible and filters.hide_gitignored },
      nil, opts.find_args, on_insert, on_exit)
  end
end

M.find_files = function(opts)
  local filters = opts.filtered_items
  local full_path_words = opts.find_by_full_path_words
  local regex, glob = nil, nil
  local fuzzy_finder_mode = opts.fuzzy_finder_mode

  glob = opts.term
  if glob:sub(1) ~= "*" then
    glob = "*" .. glob
  end
  if glob:sub(-1) ~= "*" then
    glob = glob .. "*"
  end

  M.filter_files_external(get_find_command(opts), opts.path, glob, regex, full_path_words,
    { directory = fuzzy_finder_mode == "directory" },
    { dotfiles = not filters.visible and filters.hide_dotfiles,
      gitignore = not filters.visible and filters.hide_gitignored },
    opts.limit or 200, opts.find_args, opts.on_insert, opts.on_exit)
end

return M
