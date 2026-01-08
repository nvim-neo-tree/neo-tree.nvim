local proxy = {}

---@class neotree.utils.ProxyKeyPath<T>

---@class neotree.utils.ProxyKeyPath
---@field [integer] any

---@type metatable
local key_path_mt = {
  ---return human-readable form of an array of keys
  __tostring = function(key_path)
    local strparts = {}
    for i, key in ipairs(key_path) do
      if type(key) == "number" then
        strparts[#strparts + 1] = ("[%s]"):format(key)
      else
        strparts[#strparts + 1] = tostring(key)
      end
    end
    return table.concat(strparts, ".")
  end,
}

---@param arr any[]
---@param extra_key any
---@return neotree.utils.ProxyKeyPath
local new_key_path = function(arr, extra_key)
  local tbl
  if extra_key then
    tbl = { unpack(arr) }
    tbl[#tbl + 1] = extra_key
  else
    tbl = {}
  end
  return setmetatable(tbl, key_path_mt)
end

---@class neotree.utils.ProxyHooks
---@field on_assign fun(t: table, k, v, key_path: neotree.utils.ProxyKeyPath, node: table)

---@generic T : table
---@param root T The original table root
---@param key_path neotree.utils.ProxyKeyPath[]
---@param parent any
---@return T t
local function safe_table_recursive(root, key_path, parent)
  -- local parent_mt = getmetatable(parent)
  -- local accesses = parent_mt and parent_mt.accesses or {}
  -- local assignments = parent_mt and parent_mt.assignments or {}
  ---@class neotree.utils.ProxyMetatable : metatable
  local proxy_mt = {
    __index = function(t, k)
      local new_kp = new_key_path(key_path, k)
      -- accesses[#accesses + 1] = new_kp

      local proxy_branch = safe_table_recursive(root, new_kp, t)
      rawset(t, k, proxy_branch)
      return proxy_branch
    end,
    __newindex = function(t, k, v)
      -- local new_kp = new_key_path(key_path, k)
      -- assignments[#assignments + 1] = new_kp
      local node = root
      for i = 2, #key_path do
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
    key_path = key_path,
    __tostring = function()
      return tostring(key_path)
    end,
    root = root,
  }
  local wrapper = setmetatable({}, proxy_mt)
  return wrapper
end

---Return a table that proxies a different table - all methods of indexing will never error and any assignments to any nested fields will never
---overwrite the original table unless the field in question (and parent tables necessary) does not exist.
---@generic T : table
---@param label string
---@return T t
function proxy.new(dest, label)
  return safe_table_recursive(dest, new_key_path({}, label))
end

---@generic V : table
---@param proxied V?
---@param on_val fun(val: V, proxy: table?, metatable: neotree.utils.ProxyMetatable)?
---@return V?
---@return table? proxy
---@return neotree.utils.ProxyMetatable? metatable
proxy.get = function(proxied, on_val)
  assert(type(proxied) == "table", "expected table, got " .. (tostring(proxied)))
  local value, value_proxy
  local mt = assert(getmetatable(proxied))
  value_proxy = proxied
  local root = assert(mt.root)
  local key_path = assert(mt.key_path)
  value = vim.tbl_get(root, select(2, unpack(key_path)))
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
  for i = 2, #key_path - 1 do
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

---@param obj any
---@return neotree.utils.ProxyMetatable
proxy.get_proxy_metatable = function(obj)
  local mt = getmetatable(obj)
  assert(mt.key_path)
  return mt
end

return proxy
