local vim = vim
local files_nesting = require("neo-tree.sources.common.file-nesting")
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local git = require("neo-tree.git")

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
  -- avoid creating duplicate items
  if context.folders[path] or context.nesting[path] then
    return context.folders[path] or context.nesting[path]
  end

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
    item.base = item.name:match("^([-_,()%s%w%i]+)%.")
    item.ext = item.name:match("%.([-_,()%s%w%i]+)$")
    item.exts = item.name:match("^[-_,()%s%w%i]+%.(.*)")

    if files_nesting.can_have_nesting(item) then
      item.children = {}
      context.nesting[path] = item
    end
  end

  local state = context.state
  local f = state.filtered_items
  local is_not_root = not utils.is_subpath(path, context.state.path)
  if f and is_not_root then
    if f.hide_by_name[name] then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.name = true
    elseif f.never_show[name] then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.never_show = true
    elseif f.hide_dotfiles and string.sub(item.name, 1, 1) == "." then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.dotfiles = true
    elseif f.hide_gitignored and utils.truthy(state.git_ignored) then
      if git.is_ignored(state.git_ignored, path, _type) then
        item.filtered_by = item.filtered_by or {}
        item.filtered_by.gitignored = true
      end
    end
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

  local nesting_parent_path = files_nesting.get_parent(item)
  local nesting_parent = context.nesting[nesting_parent_path]

  if
    nesting_parent_path
    and not nesting_parent
    and utils.truthy(vim.loop.fs_stat(nesting_parent_path))
  then
    local success
    success, nesting_parent = pcall(create_item, context, nesting_parent_path)
    if not success then
      log.error("error, creating item for ", nesting_parent_path)
    end
  end

  local parent = context.folders[item.parent_path]
  if not utils.truthy(item.parent_path) then
    return
  end
  if parent == nil and nesting_parent == nil then
    local success
    success, parent = pcall(create_item, context, item.parent_path, "directory")
    if not success then
      log.error("error creating item for ", item.parent_path)
    end
    context.folders[parent.id] = parent
    set_parents(context, parent)
  end
  table.insert((nesting_parent and nesting_parent.children) or parent.children, item)
  context.existing_items[item.id] = true

  if item.filtered_by == nil and type(parent.filtered_by) == "table" then
    item.filtered_by = vim.deepcopy(parent.filtered_by)
  end
end

local create_context = function(state)
  local context = {
    state = state,
    folders = {},
    nesting = {},
    existing_items = {},
  }
  return context
end

return {
  create_context = create_context,
  create_item = create_item,
  deep_sort = deep_sort,
}
