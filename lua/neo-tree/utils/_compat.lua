local compat = {}
local uv = vim.uv or vim.loop
---@return boolean
compat.noref = function()
  return vim.fn.has("nvim-0.10") == 1 and true or {} --[[@as boolean]]
end

---source: https://github.com/Validark/Lua-table-functions/blob/master/table.lua
---Moves elements [f, e] from array a1 into a2 starting at index t
---table.move implementation
---@generic T: table
---@param a1 T from which to draw elements from range
---@param f integer starting index for range
---@param e integer ending index for range
---@param t integer starting index to move elements from a1 within [f, e]
---@param a2 T the second table to move these elements to
---@default a2 = a1
---@returns a2
local table_move = function(a1, f, e, t, a2)
  a2 = a2 or a1
  t = t + e

  for i = e, f, -1 do
    t = t - 1
    a2[t] = a1[i]
  end

  return a2
end
---source:
compat.table_move = table.move or table_move

---@vararg any
local table_pack = function(...)
  -- Returns a new table with parameters stored into an array, with field "n" being the total number of parameters
  local t = { ... }
  ---@diagnostic disable-next-line: inject-field
  t.n = #t
  return t
end
compat.table_pack = table.pack or table_pack

--- Split a Windows path into a prefix and a body, such that the body can be processed like a POSIX
--- path. The path must use forward slashes as path separator.
---
--- Does not check if the path is a valid Windows path. Invalid paths will give invalid results.
---
--- Examples:
--- - `//./C:/foo/bar` -> `//./C:`, `/foo/bar`
--- - `//?/UNC/server/share/foo/bar` -> `//?/UNC/server/share`, `/foo/bar`
--- - `//./system07/C$/foo/bar` -> `//./system07`, `/C$/foo/bar`
--- - `C:/foo/bar` -> `C:`, `/foo/bar`
--- - `C:foo/bar` -> `C:`, `foo/bar`
---
--- @param path string Path to split.
--- @return string, string, boolean : prefix, body, whether path is invalid.
local function split_windows_path(path)
  local prefix = ""

  --- Match pattern. If there is a match, move the matched pattern from the path to the prefix.
  --- Returns the matched pattern.
  ---
  --- @param pattern string Pattern to match.
  --- @return string|nil Matched pattern
  local function match_to_prefix(pattern)
    local match = path:match(pattern)

    if match then
      prefix = prefix .. match --[[ @as string ]]
      path = path:sub(#match + 1)
    end

    return match
  end

  local function process_unc_path()
    return match_to_prefix("[^/]+/+[^/]+/+")
  end

  if match_to_prefix("^//[?.]/") then
    -- Device paths
    local device = match_to_prefix("[^/]+/+")

    -- Return early if device pattern doesn't match, or if device is UNC and it's not a valid path
    if not device or (device:match("^UNC/+$") and not process_unc_path()) then
      return prefix, path, false
    end
  elseif match_to_prefix("^//") then
    -- Process UNC path, return early if it's invalid
    if not process_unc_path() then
      return prefix, path, false
    end
  elseif path:match("^%w:") then
    -- Drive paths
    prefix, path = path:sub(1, 2), path:sub(3)
  end

  -- If there are slashes at the end of the prefix, move them to the start of the body. This is to
  -- ensure that the body is treated as an absolute path. For paths like C:foo/bar, there are no
  -- slashes at the end of the prefix, so it will be treated as a relative path, as it should be.
  local trailing_slash = prefix:match("/+$")

  if trailing_slash then
    prefix = prefix:sub(1, -1 - #trailing_slash)
    path = trailing_slash .. path --[[ @as string ]]
  end

  return prefix, path, true
end

--- Resolve `.` and `..` components in a POSIX-style path. This also removes extraneous slashes.
--- `..` is not resolved if the path is relative and resolving it requires the path to be absolute.
--- If a relative path resolves to the current directory, an empty string is returned.
---
--- @see M.normalize()
--- @param path string Path to resolve.
--- @return string Resolved path.
local function path_resolve_dot(path)
  local is_path_absolute = vim.startswith(path, "/")
  local new_path_components = {}

  for component in vim.gsplit(path, "/") do
    if component == "." or component == "" then -- luacheck: ignore 542
      -- Skip `.` components and empty components
    elseif component == ".." then
      if #new_path_components > 0 and new_path_components[#new_path_components] ~= ".." then
        -- For `..`, remove the last component if we're still inside the current directory, except
        -- when the last component is `..` itself
        table.remove(new_path_components)
      elseif is_path_absolute then -- luacheck: ignore 542
        -- Reached the root directory in absolute path, do nothing
      else
        -- Reached current directory in relative path, add `..` to the path
        table.insert(new_path_components, component)
      end
    else
      table.insert(new_path_components, component)
    end
  end

  return (is_path_absolute and "/" or "") .. table.concat(new_path_components, "/")
end

local passwd = uv.os_get_passwd()
---@type string?
local user = passwd and passwd.username or nil

local path_segment_ends = { "/", "\\", "" }
---@param path string
---@param i integer
---@return boolean
local function path_segment_ends_at(path, i)
  return vim.tbl_contains(path_segment_ends, path:sub(i, i))
end
--- A modified vim.fs.normalize from neovim 0.11, with proper home expansion
function compat.fs_normalize(path, opts)
  opts = opts or {}

  local win = opts.win == nil and require("neo-tree.utils").is_windows or not not opts.win
  local os_sep = win and "\\" or "/"

  -- Empty path is already normalized
  if path == "" then
    return ""
  end

  if path:sub(1, 1) == "~" then
    local home = uv.os_homedir() or "~" --- @type string
    if home:sub(-1) == os_sep then
      home = home:sub(1, -2)
    end

    if path_segment_ends_at(path, 2) then
      path = home .. path:sub(2)
    elseif user and vim.startswith(path, "~" .. user) and path_segment_ends_at(path, 2 + #user) then
      path = home .. path:sub(#user + 2) --- @type string
    end
  end

  -- Expand environment variables if `opts.expand_env` isn't `false`
  if opts.expand_env == nil or opts.expand_env then
    path = path:gsub("%$([%w_]+)", uv.os_getenv) --- @type string
  end

  if win then
    -- Convert path separator to `/`
    path = path:gsub(os_sep, "/")
  end

  -- Check for double slashes at the start of the path because they have special meaning
  local double_slash = false
  if not opts._fast then
    double_slash = vim.startswith(path, "//") and not vim.startswith(path, "///")
  end

  local prefix = ""

  if win then
    local is_valid --- @type boolean
    -- Split Windows paths into prefix and body to make processing easier
    prefix, path, is_valid = split_windows_path(path)

    -- If path is not valid, return it as-is
    if not is_valid then
      return prefix .. path
    end

    -- Ensure capital drive and remove extraneous slashes from the prefix
    prefix = prefix:gsub("^%a:", string.upper):gsub("/+", "/")
  end

  if not opts._fast then
    -- Resolve `.` and `..` components and remove extraneous slashes from path, then recombine prefix
    -- and path.
    path = path_resolve_dot(path)
  end

  -- Preserve leading double slashes as they indicate UNC paths and DOS device paths in
  -- Windows and have implementation-defined behavior in POSIX.
  path = (double_slash and "/" or "") .. prefix .. path

  -- Change empty path to `.`
  if path == "" then
    path = "."
  end

  return path
end

return compat
