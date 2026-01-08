local utils = require("neo-tree.utils")
local proxy = require("neo-tree.utils.proxy")

local M = {}

local migrations = {}

M.show_migrations = function()
  if #migrations > 0 then
    local content = {}
    for _, message in ipairs(migrations) do
      vim.list_extend(content, vim.split("\n## " .. message, "\n", { trimempty = false }))
    end
    local header = "# Neo-tree configuration has been updated. Please review the changes below."
    table.insert(content, 1, header)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buflisted = false
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_name(buf, "Neo-tree migrations")
    vim.defer_fn(function()
      vim.cmd(string.format("%ssplit", #content))
      vim.api.nvim_win_set_buf(0, buf)
    end, 100)
  end
end

---@generic O, N
---@param old O
---@param new N
---@param converter (fun(old: O):N)?
M.moved = function(old, new, converter)
  if proxy.get(new) ~= nil then
    -- new value already exists
    return
  end
  local old_val = proxy.get(old)
  if old_val == nil then
    -- old value doesn't exist
    return
  end
  if type(converter) == "function" then
    old_val = converter(old_val)
  end

  proxy.set(new, old_val)
  proxy.set(old, nil)
  migrations[#migrations + 1] = ("The `%s` option has been deprecated, please use `%s` instead."):format(
    old,
    new
  )
end

---@param proxied any
M.moved_inside = function(proxied, new_inside, converter)
  local old_value = proxy.get(proxied)
  if type(old_value) ~= "nil" and type(old_value) ~= "table" then
    if type(converter) == "function" then
      old_value = converter(old_value)
    end
    local tbl = {
      [new_inside] = old_value,
    }
    proxy.set(proxied, tbl)
    migrations[#migrations + 1] = ("The `%s` option has been replaced with a table, please move to `%s`."):format(
      proxied,
      tostring(proxied) .. "." .. new_inside
    )
  end
end

---@param proxied any
---@param desc string?
M.removed = function(proxied, desc)
  if proxy.get(proxied) ~= nil then
    proxy.set(proxied, nil)
    migrations[#migrations + 1] = table.concat({
      ("The `%s` option has been removed."):format(proxied),
      desc,
    }, "\n")
  end
end

---@generic T
---@param proxied T
---@param old_value T
---@param new_value T
M.renamed_value = function(proxied, old_value, new_value)
  local value = proxy.get(proxied)
  if value == old_value then
    proxy.set(proxied, new_value)
    migrations[#migrations + 1] = ("The `%s=%s` option has been renamed to `%s`."):format(
      proxied,
      old_value,
      new_value
    )
  end
end

---@return neotree.Config.SourceSelector.Item[]
local tab_to_source_migrator = function(labels)
  ---@type neotree.Config.SourceSelector.Item[]
  local converted_sources = {}
  for entry, label in pairs(labels) do
    ---@type neotree.Config.SourceSelector.Item
    local converted_source = { source = entry, name = label }
    table.insert(converted_sources, converted_source)
  end
  return converted_sources
end

---@param user_config neotree.Config
M.migrate = function(user_config)
  migrations = {}

  ---@return boolean
  local opposite = function(value)
    return not value
  end

  ---@class neotree._deprecated.Config : neotree.Config
  ---@field filesystem neotree._deprecated.Config.Filesystem?
  ---@field buffers neotree._deprecated.Config.Buffers?
  ---@field open_files_do_not_replace_filetypes string[]?
  ---@field source_selector neotree._deprecated.Config.SourceSelector?
  ---@field close_floats_on_escape_key boolean?
  ---@field enable_normal_mode_for_inputs boolean?
  local old = proxy.new(user_config) --[[@as neotree._deprecated.Config]]
  local new = proxy.new(user_config) --[[@as neotree.Config]]
  local old_fs_filters = old.filesystem.filters

  ---@class neotree._deprecated.Config.Filesystem : neotree.Config.Filesystem
  ---@field filters neotree._deprecated.Config.Filesystem.Filters?
  ---@field filtered_items neotree._deprecated.Config.Filesystem.FilteredItems?
  ---@field hijack_netrw_behavior neotree.Config.HijackNetrwBehavior|"open_split"?
  ---@field follow_current_file boolean?

  ---@class neotree._deprecated.Config.Buffers : neotree.Config.Buffers
  ---@field follow_current_file boolean?

  if proxy.get(old_fs_filters) then
    ---@class neotree._deprecated.Config.Filesystem.Filters : neotree.Config.Filesystem.FilteredItems
    ---@field show_hidden boolean?
    ---@field respect_gitignore boolean?
    ---@field gitignore_source any

    assert(old_fs_filters)
    M.moved(old_fs_filters, new.filesystem.filtered_items)
    M.moved(old_fs_filters.show_hidden, new.filesystem.filtered_items.hide_dotfiles, opposite)
    M.moved(old_fs_filters.respect_gitignore, new.filesystem.filtered_items.hide_gitignored)
    M.removed(old_fs_filters.gitignore_source)
  end

  ---@class neotree._deprecated.Config.Filesystem.FilteredItems : neotree.Config.Filesystem.FilteredItems
  ---@field gitignore_source any
  M.removed(old.filesystem.filtered_items.gitignore_source)

  M.moved(old.open_files_do_not_replace_filetypes, new.open_files_do_not_replace_types)

  ---@class neotree._deprecated.Config.SourceSelector : neotree.Config.SourceSelector
  ---@field tab_labels table<string, string>
  M.moved(old.source_selector.tab_labels, new.source_selector.sources, tab_to_source_migrator)

  M.renamed_value(old.filesystem.hijack_netrw_behavior, "open_split", "open_current")

  M.renamed_value(old.filesystem.window.position, "split", "current")
  M.renamed_value(old.buffers.window.position, "split", "current")
  M.renamed_value(old.git_status.window.position, "split", "current")

  M.moved_inside(old.filesystem.follow_current_file, "enabled")
  M.moved_inside(old.buffers.follow_current_file, "enabled")

  -- v3.x
  M.removed(old.close_floats_on_escape_key)

  -- v4.x
  M.removed(
    old.enable_normal_mode_for_inputs,
    [[
Please use `neo_tree_popup_input_ready` event instead and call `stopinsert` inside the handler.
<https://github.com/nvim-neo-tree/neo-tree.nvim/pull/1372>

See instructions in `:h neo-tree-events` for more details.

```lua
event_handlers = {
  {
    event = "neo_tree_popup_input_ready",
    ---@param args { bufnr: integer, winid: integer }
    handler = function(args)
      vim.cmd("stopinsert")
      vim.keymap.set("i", "<esc>", vim.cmd.stopinsert, { noremap = true, buffer = args.bufnr })
    end,
  }
}
```
]]
  )

  return migrations
end

return M
