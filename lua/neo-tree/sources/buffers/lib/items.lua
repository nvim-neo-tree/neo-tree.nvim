local vim = vim
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local file_items = require("neo-tree.sources.common.file-items")

local M = {}

---Get a table of all open buffers, along with all parent paths of those buffers.
---The paths are the keys of the table, and all the values are 'true'.
M.get_open_buffers = function(state)
  if state.loading then
    return
  end
  state.loading = true
  local context = file_items.create_context(state)
  -- Create root folder
  local root = file_items.create_item(context, state.path, "directory")
  root.name = vim.fn.fnamemodify(root.path, ":~")
  root.loaded = true
  root.search_pattern = state.search_pattern
  context.folders[root.path] = root

  local bufs = vim.api.nvim_list_bufs()
  for _, b in ipairs(bufs) do
    local path = vim.api.nvim_buf_get_name(b)
    local rootsub = path:sub(1, #state.path)
    -- make sure this is within the root path
    if rootsub == state.path then
      local is_loaded = vim.api.nvim_buf_is_loaded(b)
      if is_loaded or state.show_unloaded then
        local bufnr = vim.api.nvim_buf_get_number(b)
        local is_listed = vim.fn.buflisted(bufnr)
        if is_listed == 1 then
          local success, item = pcall(file_items.create_item, context, path, "file")
          if success then
            item.extra = {
              bufnr = bufnr,
              bufhandle = b,
              is_listed = is_listed,
            }
          else
            print("Error creating item for " .. path .. ": " .. item)
          end
        end
      end
    end
  end

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
