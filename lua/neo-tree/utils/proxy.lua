local proxy = {}

---@class neotree.utils.KeyPath
---@field [integer] any

---@param key_path neotree.utils.KeyPath
proxy._key_path_tostring = function(key_path)
  local strparts = {}
  for i, key in ipairs(key_path) do
    if type(key) == "number" then
      strparts[#strparts + 1] = ("[%s]"):format(key)
    else
      strparts[#strparts + 1] = tostring(key)
    end
  end
  return table.concat(strparts, ".")
end

---@type metatable
local key_path_mt = {
  ---return human-readable form of an array of keys
  __tostring = proxy._key_path_tostring,
}

---@param arr any[]
---@param extra_key any
---@return neotree.utils.KeyPath
proxy._new_key_path = function(arr, extra_key)
  local tbl
  if extra_key then
    tbl = { unpack(arr) }
    tbl[#tbl + 1] = extra_key
  else
    tbl = {}
  end
  return setmetatable(tbl, key_path_mt)
end

local proxy_tostring = function(t)
  return tostring(getmetatable(t).key_path)
end

---@generic T : table
---@param root T The original table root
---@param key_path neotree.utils.KeyPath
---@param metadata neotree.utils.ProxyMetadata?
---@return T t
local function new_proxy_recursive(root, key_path, metadata)
  ---@class neotree.utils.ProxyMetatable : metatable
  local proxy_mt = {
    __index = function(t, k)
      local new_kp = proxy._new_key_path(key_path, k)
      if metadata then
        if metadata.accesses then
          local accesses = metadata.accesses
          accesses[#accesses + 1] = new_kp
        end
        if metadata.return_primitives then
          local val = vim.tbl_get(root, unpack(new_kp))
          if type(val) ~= "table" then
            return val
          end
        end
      end

      local proxy_branch = new_proxy_recursive(root, new_kp, metadata)
      rawset(t, k, proxy_branch)
      return proxy_branch
    end,
    __newindex = function(t, k, v)
      local new_kp = proxy._new_key_path(key_path, k)
      if metadata then
        if metadata.assignments then
          local assignments = metadata.assignments
          assignments[#assignments + 1] = new_kp
        end
      end
      local node = root
      for i = 1, #key_path do
        local key = key_path[i]
        local val = node[key]
        if val == nil then
          node[key] = {}
        end
        node = node[key]
        if type(node) ~= "table" then
          return
        end
      end
      node[k] = v
    end,
    proxy = true,
    root = root,
    ---@type neotree.utils.ProxyMetadata?
    metadata = nil,
    key_path = key_path,
    __tostring = proxy_tostring,
  }
  local wrapper = setmetatable({}, proxy_mt)
  return wrapper
end

---Return a table that proxies a different table - all methods of indexing will never error and any assignments to any nested fields will never
---overwrite the original table unless the field in question does not exist.
---@generic T : table
---@param t T
---@param enable_tracking boolean? Enable access/assignment tracking
---@param return_primitives boolean? Return primitives when accessed instead of returning a new
---@return T t
---@return neotree.utils.ProxyMetadata? metadata
function proxy.new(t, enable_tracking, return_primitives)
  local metadata
  if enable_tracking or return_primitives then
    ---@class neotree.utils.ProxyMetadata
    metadata = {
      ---@type neotree.utils.KeyPath[]?
      accesses = enable_tracking and {} or nil,
      ---@type neotree.utils.KeyPath[]?
      assignments = enable_tracking and {} or nil,
      return_primitives = return_primitives,
    }
  end
  local p = new_proxy_recursive(t, proxy._new_key_path({}), metadata)
  getmetatable(p).metadata = metadata
  return p, metadata
end

---@generic V : table
---@param proxied V?
---@param on_val fun(val: V, proxy: V?, metatable: neotree.utils.ProxyMetatable)?
---@return V? val
---@return V? proxy
---@return neotree.utils.ProxyMetatable? metatable
proxy.get = function(proxied, on_val)
  assert(type(proxied) == "table", "expected table, got " .. (tostring(proxied)))
  local value, value_proxy
  local mt = assert(getmetatable(proxied))
  ---@cast mt neotree.utils.ProxyMetatable
  value_proxy = proxied
  local root = assert(mt.root)
  local key_path = assert(mt.key_path)
  value = vim.tbl_get(root, unpack(key_path))
  if value ~= nil and on_val then
    on_val(value, value_proxy, mt)
  end
  return value, value_proxy, mt
end

---@generic V
---@param proxied V
---@param new_val V|any
---@param force boolean?
proxy.set = function(proxied, new_val, force)
  assert(type(proxied) == "table")
  local mt = assert(getmetatable(proxied))
  local root = assert(mt.root)
  local key_path = assert(mt.key_path)
  local node = root
  for i = 1, #key_path - 1 do
    local key = key_path[i]
    local val = node[key]
    if val == nil then
      node[key] = {}
    elseif type(val) ~= "table" then
      if not force then
        -- primitive in the path, stop
        return
      else
        node[key] = {}
      end
    end
    node = node[key]
  end
  local last_key = assert(key_path[#key_path])
  local old_val = node[last_key]
  node[last_key] = new_val
  return old_val
end

return proxy
