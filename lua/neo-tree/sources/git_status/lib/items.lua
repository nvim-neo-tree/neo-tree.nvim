local vim = vim
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local file_items = require("neo-tree.sources.common.file-items")
local popups = require("neo-tree.ui.popups")

local M = {}

---Get a table of all open buffers, along with all parent paths of those buffers.
---The paths are the keys of the table, and all the values are 'true'.
M.get_git_status = function(state)
  if state.loading then
    return
  end
  state.loading = true
  local status_lookup, project_root = utils.get_git_status(true)
  state.path = project_root or state.path or vim.fn.getcwd()
  local context = file_items.create_context(state)
  -- Create root folder
  local root = file_items.create_item(context, state.path, "directory")
  root.name = vim.fn.fnamemodify(root.path, ":~")
  root.loaded = true
  root.search_pattern = state.search_pattern
  context.folders[root.path] = root

  for path, status in pairs(status_lookup) do
    local success, item = pcall(file_items.create_item, context, path, "file")
    item.status = status
    if success then
      item.extra = {
        git_status = status,
      }
    else
      print("Error creating item for " .. path .. ": " .. item)
    end
  end

  state.git_status_lookup = status_lookup
  state.default_expanded_nodes = {}
  for id, _ in pairs(context.folders) do
    table.insert(state.default_expanded_nodes, id)
  end
  file_items.deep_sort(root.children)
  state.before_render(state)
  renderer.show_nodes({ root }, state)
  state.loading = false
end

return M
