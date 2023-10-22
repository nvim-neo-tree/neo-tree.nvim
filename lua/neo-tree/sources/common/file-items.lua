local vim = vim
local file_nesting = require("neo-tree.sources.common.file-nesting")
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")

local function sort_items(a, b)
  if a.type == b.type then
    return a.path < b.path
  else
    return a.type < b.type
  end
end

local function sort_items_case_insensitive(a, b)
  if a.type == b.type then
    return a.path:lower() < b.path:lower()
  else
    return a.type < b.type
  end
end

---Creates a sort function the will sort by the values returned by the field provider.
---@param field_provider function a function that takes an item and returns a value to
--                        sort by.
---@param fallback_sort_function function a sort function to use if the field provider
--                                returns the same value for both items.
local function make_sort_function(field_provider, fallback_sort_function, direction)
  return function(a, b)
    if a.type == b.type then
      local a_field = field_provider(a)
      local b_field = field_provider(b)
      if a_field == b_field then
        return fallback_sort_function(a, b)
      else
        if direction < 0 then
          return a_field > b_field
        else
          return a_field < b_field
        end
      end
    else
      return a.type < b.type
    end
  end
end

local function sort_function_is_valid(func)
  if func == nil then
    return false
  end

  local a = { type = "dir", path = "foo" }
  local b = { type = "dir", path = "baz" }

  local success, result = pcall(func, a, b)
  if success and type(result) == "boolean" then
    return true
  end

  log.error("sort function isn't valid ", result)
  return false
end

local function deep_sort(tbl, sort_func, field_provider, direction)
  if sort_func == nil then
    local config = require("neo-tree").config
    if sort_function_is_valid(config.sort_function) then
      sort_func = config.sort_function
    elseif config.sort_case_insensitive then
      sort_func = sort_items_case_insensitive
    else
      sort_func = sort_items
    end
    if field_provider ~= nil then
      sort_func = make_sort_function(field_provider, sort_func, direction)
    end
  end
  table.sort(tbl, sort_func)
  for _, item in pairs(tbl) do
    if item.type == "directory" or item.children ~= nil then
      deep_sort(item.children, sort_func)
    end
  end
end

local advanced_sort = function(tbl, state)
  local sort_func = state.sort_function_override
  local field_provider = state.sort_field_provider
  local direction = state.sort and state.sort.direction or 1
  deep_sort(tbl, sort_func, field_provider, direction)
end

local create_item, set_parents

function create_item(context, path, _type, bufnr)
  local parent_path, name = utils.split_path(path)
  local id = path
  if path == "[No Name]" and bufnr then
    parent_path = context.state.path
    name = "[No Name]"
    id = tostring(bufnr)
  else
    -- avoid creating duplicate items
    if context.folders[path] or context.nesting[path] or context.item_exists[path] then
      return context.folders[path] or context.nesting[path] or context.item_exists[path]
    end
  end

  if _type == nil then
    local stat = vim.loop.fs_stat(path)
    _type = stat and stat.type or "unknown"
  end
  local item = {
    id = id,
    name = name,
    parent_path = parent_path,
    path = path,
    type = _type,
  }
  if item.type == "link" then
    item.is_link = true
    item.link_to = vim.loop.fs_realpath(path)
    if item.link_to ~= nil then
      item.type = vim.loop.fs_stat(item.link_to).type
    end
  end
  if item.type == "directory" then
    item.children = {}
    item.loaded = false
    context.folders[path] = item
    if context.state.search_pattern then
      table.insert(context.state.default_expanded_nodes, item.id)
    end
  else
    item.base = item.name:match("^([-_,()%s%w%i]+)%.")
    item.ext = item.name:match("%.([-_,()%s%w%i]+)$")
    item.exts = item.name:match("^[-_,()%s%w%i]+%.(.*)")
    item.name_lcase = item.name:lower()

    local nesting_callback = file_nesting.get_nesting_callback(item)
    if nesting_callback ~= nil then
      item.children = {}
      item.nesting_callback = nesting_callback
      context.nesting[path] = item
    end
  end

  item.is_reveal_target = (path == context.path_to_reveal)
  local state = context.state
  local f = state.filtered_items
  local is_not_root = not utils.is_subpath(path, context.state.path)
  if f and is_not_root then
    if f.never_show[name] then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.never_show = true
    else
      if utils.is_filtered_by_pattern(f.never_show_by_pattern, path, name) then
        item.filtered_by = item.filtered_by or {}
        item.filtered_by.never_show = true
      end
    end
    if f.always_show[name] then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.always_show = true
    end
    if f.hide_by_name[name] then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.name = true
    end
    if utils.is_filtered_by_pattern(f.hide_by_pattern, path, name) then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.pattern = true
    end
    if f.hide_dotfiles and string.sub(name, 1, 1) == "." then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.dotfiles = true
    end
    if f.hide_hidden and utils.is_hidden(path) then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.hidden = true
    end
    -- NOTE: git_ignored logic moved to job_complete
  end

  set_parents(context, item)
  if context.all_items == nil then
    context.all_items = {}
  end
  if is_not_root then
    table.insert(context.all_items, item)
  end
  return item
end

-- function to set (or create) parent folder
function set_parents(context, item, siblings)
  -- we can get duplicate items if we navigate up with open folders
  -- this is probably hacky, but it works
  if context.item_exists[item.id] then
    return
  end
  if not item.parent_path then
    return
  end

  local parent = context.folders[item.parent_path]
  if not utils.truthy(item.parent_path) then
    return
  end
  if parent == nil then
    local success
    success, parent = pcall(create_item, context, item.parent_path, "directory")
    if not success then
      log.error("error creating item for ", item.parent_path)
    end
    context.folders[parent.id] = parent
    set_parents(context, parent)
  end
  table.insert(parent.children, item)
  context.item_exists[item.id] = true

  if item.filtered_by == nil and type(parent.filtered_by) == "table" then
    item.filtered_by = vim.deepcopy(parent.filtered_by)
  end
end

---Create context to be used in other file-items functions.
---@param state table|nil The state of the file-items.
---@return table
local create_context = function(state)
  local context = {}
  -- Make the context a weak table so that it can be garbage collected
  --setmetatable(context, { __mode = 'v' })
  context.state = state
  context.folders = {}
  context.nesting = {}
  context.item_exists = {}
  context.all_items = {}
  return context
end

return {
  create_context = create_context,
  create_item = create_item,
  deep_sort = deep_sort,
  advanced_sort = advanced_sort,
}
