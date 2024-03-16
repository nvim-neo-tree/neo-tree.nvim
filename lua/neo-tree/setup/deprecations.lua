local utils = require("neo-tree.utils")

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
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "buflisted", false)
    vim.api.nvim_buf_set_option(buf, "swapfile", false)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
    vim.api.nvim_buf_set_name(buf, "Neo-tree migrations")
    vim.defer_fn(function()
      vim.cmd(string.format("%ssplit", #content))
      vim.api.nvim_win_set_buf(0, buf)
    end, 100)
  end
end

M.migrate = function(config)
  migrations = {}

  local moved = function(old, new, converter)
    local existing = utils.get_value(config, old)
    if type(existing) ~= "nil" then
      if type(converter) == "function" then
        existing = converter(existing)
      end
      utils.set_value(config, old, nil)
      utils.set_value(config, new, existing)
      migrations[#migrations + 1] =
        string.format("The `%s` option has been deprecated, please use `%s` instead.", old, new)
    end
  end

  local moved_inside = function(old, new_inside, converter)
    local existing = utils.get_value(config, old)
    if type(existing) ~= "nil" and type(existing) ~= "table" then
      if type(converter) == "function" then
        existing = converter(existing)
      end
      utils.set_value(config, old, {})
      local new = old .. "." .. new_inside
      utils.set_value(config, new, existing)
      migrations[#migrations + 1] =
        string.format("The `%s` option is replaced with a table, please move to `%s`.", old, new)
    end
  end

  local removed = function(key, desc)
    local value = utils.get_value(config, key)
    if type(value) ~= "nil" then
      utils.set_value(config, key, nil)
      migrations[#migrations + 1] =
        string.format("The `%s` option has been removed.\n%s", key, desc or "")
    end
  end

  local renamed_value = function(key, old_value, new_value)
    local value = utils.get_value(config, key)
    if value == old_value then
      utils.set_value(config, key, new_value)
      migrations[#migrations + 1] =
        string.format("The `%s=%s` option has been renamed to `%s`.", key, old_value, new_value)
    end
  end

  local opposite = function(value)
    return not value
  end

  local tab_to_source_migrator = function(labels)
    local converted_sources = {}
    for entry, label in pairs(labels) do
      table.insert(converted_sources, { source = entry, display_name = label })
    end
    return converted_sources
  end

  moved("filesystem.filters", "filesystem.filtered_items")
  moved("filesystem.filters.show_hidden", "filesystem.filtered_items.hide_dotfiles", opposite)
  moved("filesystem.filters.respect_gitignore", "filesystem.filtered_items.hide_gitignored")
  moved("open_files_do_not_replace_filetypes", "open_files_do_not_replace_types")
  moved("source_selector.tab_labels", "source_selector.sources", tab_to_source_migrator)
  removed("filesystem.filters.gitignore_source")
  removed("filesystem.filter_items.gitignore_source")
  renamed_value("filesystem.hijack_netrw_behavior", "open_split", "open_current")
  for _, source in ipairs({ "filesystem", "buffers", "git_status" }) do
    renamed_value(source .. "window.position", "split", "current")
  end
  moved_inside("filesystem.follow_current_file", "enabled")
  moved_inside("buffers.follow_current_file", "enabled")

  -- v3.x
  removed("close_floats_on_escape_key")

  -- v4.x
  removed(
    "enable_normal_mode_for_inputs",
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
