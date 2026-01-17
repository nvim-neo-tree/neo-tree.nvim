local renderer = require("neo-tree.ui.renderer")
local file_items = require("neo-tree.sources.common.file-items")
local log = require("neo-tree.log")
local git = require("neo-tree.git")

local M = {}

---Get a table of all git statuses in the current repo, along with all parent paths.
---The paths are the keys of the table, and all the values are 'true'.
---@param state neotree.StateWithTree
M.get_git_status = function(state)
  if state.loading then
    return
  end
  state.loading = true
  local status_lookup, project_root, status_lookup_over_base =
    git.status(state.path, state.git_base_by_worktree, false, {
      untracked_files = "all",
    })
  state.path = project_root or state.path or vim.fn.getcwd()
  local context = file_items.create_context()
  context.state = state
  -- Create root folder
  local root = file_items.create_item(context, state.path, "directory") --[[@as neotree.FileItem.Directory]]
  root.name = vim.fn.fnamemodify(root.path, ":~")
  root.loaded = true
  root.search_pattern = state.search_pattern
  context.folders[root.path] = root

  local status_lookups = {}
  if status_lookup then
    status_lookups[#status_lookups + 1] = status_lookup
  end
  if status_lookup_over_base then
    status_lookups[#status_lookups + 1] = status_lookup_over_base
  end
  for i, sl in ipairs(status_lookups) do
    for path, status in pairs(sl) do
      ---@type string
      local normalized_status
      if type(status) ~= "table" and status ~= "!" then
        local success, item = pcall(file_items.create_item, context, path)
        if not success then
          log.error("Error creating git_status item for " .. path .. ": " .. item)
        else
          if item.type == "unknown" then
            item.type = "file"
          end
          item.status = normalized_status
          item.extra = {
            git_status = status,
          }
        end
      end
    end
  end

  state.default_expanded_nodes = {}
  for id, _ in pairs(context.folders) do
    table.insert(state.default_expanded_nodes, id)
  end
  file_items.advanced_sort(root.children, state)
  renderer.show_nodes({ root }, state)
  state.loading = false
end

return M
