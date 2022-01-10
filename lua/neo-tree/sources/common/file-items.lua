local vim = vim
local utils = require("neo-tree.utils")

local function sort_items(a, b)
  if a.type == b.type then
    return a.path < b.path
  else
    return a.type < b.type
  end
end

local function deep_sort(tbl)
  table.sort(tbl, sort_items)
  for _, item in pairs(tbl) do
    if item.type == "directory" then
      deep_sort(item.children)
    end
  end
end

local create_item, set_parents

function create_item(context, path, _type)
  local parent_path, name = utils.split_path(path)
  if _type == nil then
    local stat = vim.loop.fs_stat(path)
    _type = stat and stat.type or "unknown"
  end
  local item = {
    id = path,
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
    item.ext = item.name:match("%.(%w+)$")
  end
  set_parents(context, item)
  return item
end

-- function to set (or create) parent folder
function set_parents(context, item)
  -- we can get duplicate items if we navigate up with open folders
  -- this is probably hacky, but it works
  if context.existing_items[item.id] then
    return
  end
  if not item.parent_path then
    return
  end
  local parent = context.folders[item.parent_path]
  if parent == nil then
    local success
    success, parent = pcall(create_item, context, item.parent_path, "directory")
    if not success then
      print("error creating item for ", item.parent_path)
    end
    context.folders[parent.id] = parent
    set_parents(context, parent)
  end
  table.insert(parent.children, item)
  context.existing_items[item.id] = true
end

local create_context = function(state)
  local context = {
    state = state,
    folders = {},
    existing_items = {},
  }
  return context
end

return {
  create_context = create_context,
  create_item = create_item,
  deep_sort = deep_sort,
}
