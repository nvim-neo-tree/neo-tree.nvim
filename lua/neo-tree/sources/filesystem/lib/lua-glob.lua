---From https://github.com/sumneko/lua-glob/blob/master/glob.lua
local utils = require("neo-tree.utils")

---@class neotree.lib.LuaGlob
local M = {}
M.__index = M

---@class neotree.lib.LuaGlob.Options
---@field ignoreCase? boolean
---@field asGitIgnore? boolean
---@field root? string

---@class neotree.lib.LuaGlob.Interface
---@field type? fun(path: string):('file'|'directory'|nil)
---@field list? fun(path: string):string[]?
---@field patterns? fun(path: string):string[]?

---@param pat string
---@param start integer
local function parsePatternRangePart(pat, start)
  local pack = {
    kind = "range",
    ranges = {},
    singles = {},
  }
  local index = start
  while index <= #pat do
    local char = pat:sub(index, index)
    index = index + 1
    if char == "]" then
      return pack, index
    end
    if char == "\\" then
      char = pat:sub(index, index)
      index = index + 1
    end
    local peek = pat:sub(index, index)
    if peek == "-" then
      local stop = pat:sub(index + 1, index + 1)
      pack.ranges[#pack.ranges + 1] = { char, stop }
      index = index + 2
    else
      pack.singles[#pack.singles + 1] = char
    end
  end
  return pack, index
end

---@param pat string
---@param start integer
local function parsePatternBracePart(pat, start)
  local s, e, a1, a2 = pat:find("(%a)%.%.(%a)%}", start)
  if s then
    if a1 > a2 then
      a1, a2 = a2, a1
    end
    return {
      kind = "brace",
      alphaRange = { a1, a2 },
    }, e + 1
  end
  local s, e, n1, n2 = pat:find("(%d+)%.%.(%d+)%}", start)
  if s then
    n1 = tonumber(n1)
    n2 = tonumber(n2)
    if n1 > n2 then
      n1, n2 = n2, n1
    end
    return {
      kind = "brace",
      numberRange = { n1, n2 },
    }, e + 1
  end
  local pack = {
    kind = "brace",
    singles = {},
  }
  local index = start
  local buf = ""
  while index <= #pat do
    local pos, _, char = pat:find("([%,%}%\\])", index)
    if not pos then
      buf = buf .. pat:sub(index)
      if #buf > 0 then
        pack.singles[#pack.singles + 1] = buf
      end
      index = #pat + 1
      break
    end
    if pos > index then
      buf = buf .. pat:sub(index, pos - 1)
    end
    index = pos + 1
    if char == "}" then
      if #buf > 0 then
        pack.singles[#pack.singles + 1] = buf
      end
      return pack, index
    elseif char == "," then
      if #buf > 0 then
        pack.singles[#pack.singles + 1] = buf
      end
      buf = ""
    elseif char == "\\" then
      buf = buf .. pat:sub(index, index)
      index = index + 1
    else
      buf = buf .. char
    end
  end
  return pack, index
end

---@private
---@param pat string
---@return table
---@return integer
function M:parsePatternOr(pat)
  local result = {
    kind = "or",
    childs = {},
  }

  pat = pat:sub(2)
  while true do
    local pattern, pos = self:parsePattern(pat)
    if not pattern then
      break
    end
    result.childs[#result.childs + 1] = pattern
    local char = pat:sub(pos, pos)
    if char == "," then
      pat = pat:sub(pos + 1)
    elseif char == "}" then
      return result, pos + 1
    else
      return result, pos
    end
  end

  return result, #pat + 1
end

---@private
---@param a string
---@param b string
---@return boolean
function M:pathEqual(a, b)
  if self.options.ignoreCase then
    return a:lower() == b:lower()
  end
  return a == b
end

---@private
---@param pat string
---@return table
---@return integer
function M:parsePattern(pat)
  if pat:sub(1, 1) == "{" then
    return self:parsePatternOr(pat)
  end

  local result = {
    kind = "base",
    symbols = {},
  }

  pat = pat:gsub("^%s+", ""):gsub("%s+$", "")
  local last = 1
  if pat:sub(last, last) == "!" then
    result.refused = true
    last = last + 1
  end
  if pat:sub(last, last) == "/" then
    result.root = true
    last = last + 1
  elseif pat:sub(last, last + 1) == "./" then
    result.root = true
    last = last + 2
  end
  if pat:sub(-1) == "/" then
    result.onlyDirectory = true
    pat = pat:sub(1, #pat - 1)
  end
  while true do
    local start, _, char = pat:find("([%*%?%[%/%\\%{%,%}])", last)
    if not start then
      if last <= #pat then
        result.symbols[#result.symbols + 1] = pat:sub(last)
      end
      return result, #pat
    end
    if start > last then
      result.symbols[#result.symbols + 1] = pat:sub(last, start - 1)
    end
    if char == "*" then
      if pat:sub(start + 1, start + 1) == "*" then
        -- **
        result.symbols[#result.symbols + 1] = "**"
        last = start + 2
        if pat:sub(last, last) == "/" then
          last = last + 1
        end
      else
        result.symbols[#result.symbols + 1] = "*"
        last = start + 1
      end
    elseif char == "?" or char == "/" then
      result.symbols[#result.symbols + 1] = char
      last = start + 1
    elseif char == "[" then
      result.symbols[#result.symbols + 1], last = parsePatternRangePart(pat, start + 1)
    elseif char == "{" then
      result.symbols[#result.symbols + 1], last = parsePatternBracePart(pat, start + 1)
    elseif char == "\\" then
      result.symbols[#result.symbols + 1] = pat:sub(start + 1, start + 1)
      last = start + 2
    elseif char == "," or char == "}" then
      return result, start
    end
  end
end

---@param pat string
---@param base? string
function M:addPattern(pat, base)
  base = base or self.options.root or ""
  if self.options.ignoreCase then
    base = base:lower()
  end
  if not self.patternMap[base] then
    self.patternMap[base] = {}
  end
  local pattern = self:parsePattern(pat)
  table.insert(self.patternMap[base], pattern)
end

---@param op string
---@param val any
function M:setOption(op, val)
  if val == nil then
    val = true
  end
  self.options[op] = val
end

---@overload fun(self: neotree.lib.LuaGlob, key: 'type', func: fun(path: string):('file'|'directory'|nil))
---@overload fun(self: neotree.lib.LuaGlob, key: 'list', func: fun(path: string):string[]?)
---@overload fun(self: neotree.lib.LuaGlob, key: 'patterns', func: fun(path: string):string[]?)
function M:setInterface(key, func)
  if type(func) ~= "function" then
    return
  end
  self.interface[key] = func
end

---@private
function M:checkPatternByBrace(path, pat)
  if pat.singles then
    for _, single in ipairs(pat.singles) do
      if self:pathEqual(path:sub(1, #single), single) then
        return true, path:sub(#single + 1)
      end
    end
    return false
  end
  if pat.alphaRange then
    local first = pat.alphaRange[1]
    local last = pat.alphaRange[2]
    if self.options.ignoreCase then
      first = first:lower()
      last = last:lower()
    end
    if path:sub(1, 1) >= first and path:sub(1, 1) <= last then
      return true, path:sub(2)
    end
    return false
  end
  if pat.numberRange then
    local first = pat.numberRange[1]
    local last = pat.numberRange[2]
    for i = #tostring(last), #tostring(first), -1 do
      local char = path:sub(1, i)
      local num = tonumber(char)
      if num and num >= first and num <= last then
        return true, path:sub(i + 1)
      end
    end
    return false
  end
end

---@private
function M:checkPatternByRange(path, pat)
  local ignoreCase = self.options.ignoreCase
  local char = path:sub(1, 1)
  for _, range in ipairs(pat.ranges) do
    local s, e = range[1], range[2]
    if ignoreCase then
      s = s:lower()
      e = e:lower()
    end
    if char >= s and char <= e then
      return true, path:sub(2)
    end
  end
  for _, single in ipairs(pat.singles) do
    if ignoreCase then
      single = single:lower()
    end
    if char == single then
      return true, path:sub(2)
    end
  end
  return false
end

---@private
function M:checkPatternWord(path, pattern, patIndex)
  for i = patIndex, #pattern.symbols do
    local pat = pattern.symbols[i]
    if pat == "*" then
      if path == nil then
        return false
      end
      if path == "" then
        return true, i + 1
      end
      local newPath = path
      while true do
        local suc, newIndex = self:checkPatternWord(newPath, pattern, i + 1)
        if suc then
          return true, newIndex
        end
        if newPath == "" then
          return false
        end
        newPath = newPath:sub(2)
      end
      return false
    elseif pat == "?" then
      if path == nil or path == "" then
        return false
      end
      path = path:sub(2)
    elseif pat == "/" or pat == "**" then
      if path == nil or path == "" then
        return true, i
      else
        return false
      end
    elseif path == nil then
      return false
    elseif type(pat) == "string" then
      if not self:pathEqual(path:sub(1, #pat), pat) then
        return false
      end
      path = path:sub(#pat + 1)
    elseif pat.kind == "brace" then
      local ok, leftPath = self:checkPatternByBrace(path, pat)
      if not ok then
        return false
      end
      path = leftPath
    elseif pat.kind == "range" then
      local ok, leftPath = self:checkPatternByRange(path, pat)
      if not ok then
        return false
      end
      path = leftPath
    end
  end
  if path == nil or path == "" then
    return true, #pattern.symbols + 1
  end
  return false
end

---@private
---@param paths string[]
---@param pathIndex integer
---@param pattern table
---@param patIndex integer
---@return boolean
function M:checkPatternSlice(paths, pathIndex, pattern, patIndex)
  local path = paths[pathIndex]
  local pat = pattern.symbols[patIndex]
  if pat == nil then
    if pattern.onlyDirectory then
      if pathIndex < #paths then
        return true
      end
      if self.interface.type then
        local currentPath = table.concat(paths, "/", 1, pathIndex)
        local fileType = self.interface.type(currentPath)
        if fileType ~= "directory" then
          return false
        end
      end
    end
    return true
  end
  if path == nil and pat == nil then
    return true
  end
  if pat == "/" then
    return self:checkPatternSlice(paths, pathIndex + 1, pattern, patIndex + 1)
  end
  if pat == "**" then
    for i = pathIndex, #paths do
      if self:checkPatternSlice(paths, i, pattern, patIndex + 1) then
        return true
      end
    end
    return false
  end
  local ok, newIndex = self:checkPatternWord(path, pattern, patIndex)
  if not ok then
    return false
  end
  ---@cast newIndex -?
  return self:checkPatternSlice(paths, pathIndex, pattern, newIndex)
end

---@private
---@param paths string[]
---@param pattern table
---@param start integer
---@return boolean
function M:checkPattern(paths, pattern, start)
  if pattern.kind == "base" then
    if #pattern.symbols == 0 then
      return false
    end
    if pattern.root then
      return self:checkPatternSlice(paths, start, pattern, 1)
    else
      for i = start, #paths do
        if self:checkPatternSlice(paths, i, pattern, 1) then
          return true
        end
      end
      return false
    end
  elseif pattern.kind == "or" then
    for _, child in ipairs(pattern.childs) do
      if self:checkPattern(paths, child, start) then
        return true
      end
    end
    return false
  end
  return false
end

---@enum neotree.lib.LuaGlob.Status
local Statuses = {
  UNKNOWN = "unknown",
  REFUSED = "refused",
  ACCEPTED = "accepted",
}

---@param paths string[]
---@return neotree.lib.LuaGlob.Status
function M:status(paths)
  local status = "unknown"

  local function statusWithPatterns(patterns, start)
    for _, pattern in ipairs(patterns) do
      if status ~= Statuses.REFUSED and pattern.refused then
        if self:checkPattern(paths, pattern, start) then
          status = Statuses.REFUSED
        end
      elseif status ~= Statuses.ACCEPTED and not pattern.refused then
        if self:checkPattern(paths, pattern, start) then
          status = Statuses.ACCEPTED
        end
      end
    end
  end

  if self.options.asGitIgnore then
    for i = 1, #paths do
      local base = table.concat(paths, "/", 1, i - 1)
      if self.options.root then
        base = utils.path_join(self.options.root, base)
      end
      local patternKey = base
      if self.options.ignoreCase then
        patternKey = patternKey:lower()
      end
      local patterns = self.patternMap[patternKey]
      if not patterns then
        patterns = {}
        self.patternMap[patternKey] = patterns
        if self.interface.patterns then
          local newPatterns = self.interface.patterns(base)
          if type(newPatterns) == "table" then
            for _, pat in ipairs(newPatterns) do
              self:addPattern(pat, base)
            end
          end
        end
      end
      if #patterns > 0 then
        statusWithPatterns(patterns, i)
      end
    end
  else
    local patterns = self.patternMap[""] or {}
    statusWithPatterns(patterns, 1)
  end

  return status
end

---@param path string
---@return boolean? accepted
function M:check(path)
  local root = self.options.root
  if root then
    if self:pathEqual(path:sub(1, #root), root) then
      path = path:sub(#root + 1)
    else
      return false
    end
  end

  if self.options.asGitIgnore then
    local paths = {}
    for p in path:gmatch("[^/\\]+") do
      paths[#paths + 1] = p
      local status = self:status(paths)
      if status == Statuses.ACCEPTED then
        return true
      elseif status == Statuses.REFUSED then
        return false
      end
    end
    return nil
  end

  local paths = {}
  for p in path:gmatch("[^/\\]+") do
    paths[#paths + 1] = p
  end

  local status = self:status(paths)
  if status == Statuses.ACCEPTED then
    return true
  elseif status == Statuses.REFUSED then
    return false
  end
  return nil
end

---@private
---@param path string
---@return string[]
function M:toPaths(path)
  local root = self.options.root
  if root then
    if self:pathEqual(path:sub(1, #root), root) then
      path = path:sub(#root + 1)
    else
      return {}
    end
  end

  local paths = {}
  for p in path:gmatch("[^/\\]+") do
    paths[#paths + 1] = p
  end
  return paths
end

---@param root? string
---@param callback? fun(path: string)
function M:scan(root, callback)
  root = root or ""
  local checked = {}

  local function check(path)
    local checkedPath = path
    if self.options.ignoreCase then
      checkedPath = checkedPath:lower()
    end
    if checked[checkedPath] then
      return
    end
    checked[checkedPath] = true
    if #path ~= root and self:status(self:toPaths(path)) == "accepted" then
      return
    end
    local ftype
    if #path == root then
      ftype = "directory"
    else
      ftype = self.interface.type and self.interface.type(path) or nil
    end
    if not ftype then
      return
    end
    if ftype == "file" then
      if callback then
        callback(path)
      end
      return
    end
    if ftype == "directory" then
      local files = self.interface.list and self.interface.list(path) or nil
      if type(files) ~= "table" then
        return
      end
      for _, file in ipairs(files) do
        check(file)
      end
    end
  end

  check(root)
end

function M:__call(...)
  return self:check(...)
end

---@param pattern? string|string[]
---@param options? neotree.lib.LuaGlob.Options
---@param interface? neotree.lib.LuaGlob.Interface
---@return neotree.lib.LuaGlob
local function createGlob(pattern, options, interface)
  ---@class neotree.lib.LuaGlob
  local glob = setmetatable({
    ---@type table<string, table[]?>
    patternMap = {},
    ---@type neotree.lib.LuaGlob.Options
    options = {},
    ---@type neotree.lib.LuaGlob.Interface
    interface = {},
  }, M)

  if type(options) == "table" then
    for op, val in pairs(options) do
      glob:setOption(op, val)
    end
  end

  if type(pattern) == "table" then
    for _, pat in ipairs(pattern) do
      glob:addPattern(pat)
    end
  elseif pattern then
    glob:addPattern(pattern)
  end

  if type(interface) == "table" then
    for key, func in pairs(interface) do
      glob:setInterface(key, func)
    end
  end

  return glob
end

---@param pattern? string|string[]
---@param options? neotree.lib.LuaGlob.Options
---@param interface? neotree.lib.LuaGlob.Interface
---@return neotree.lib.LuaGlob
local function createGitIgnore(pattern, options, interface)
  local glob = createGlob(pattern, options, interface)
  glob:setOption("asGitIgnore", true)
  return glob
end

return {
  glob = createGlob,
  gitignore = createGitIgnore,
  Statuses = Statuses,
}
