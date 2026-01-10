-- describe("deprecation module", function()
-- local deprecations = require("neo-tree.setup.deprecations")
--   ---@type neotree._deprecated.Config
--   ---@diagnostic disable-next-line: missing-fields
--   local deprecated_config = {
--     filesystem = {
--       hijack_netrw_behavior = "open_split",
--       filters = {
--         gitignore_source = "test1",
--         show_hidden = true,
--         respect_gitignore = true,
--       },
--       filtered_items = {
--         gitignore_source = "test2",
--       },
--       follow_current_file = true,
--       window = {
--         position = "split",
--       },
--     },
--     buffers = {
--       follow_current_file = true,
--       window = {
--         position = "split",
--       },
--     },
--     git_status = {
--       window = {
--         position = "split",
--       },
--     },
--     close_floats_on_escape_key = true,
--     enable_normal_mode_for_inputs = true,
--   }
--   it("should migrate all options properly", function()
--     assert.are.same({}, deprecated_config)
--   end)
-- end)

local deprecations = require("neo-tree.setup.deprecations.init")
describe("deprecation module2", function()
  ---@type neotree._deprecated.Config
  ---@diagnostic disable-next-line: missing-fields
  local deprecated_config = {
    filesystem = {
      hijack_netrw_behavior = "open_split",
      filters = {
        gitignore_source = "test1",
        show_hidden = true,
        respect_gitignore = true,
      },
      filtered_items = {
        gitignore_source = "test2",
      },
      follow_current_file = true,
      window = {
        position = "split",
      },
    },
    buffers = {
      follow_current_file = true,
      window = {
        position = "split",
      },
    },
    git_status = {
      window = {
        position = "split",
      },
    },
    close_floats_on_escape_key = true,
    enable_normal_mode_for_inputs = true,
  }
  it("should migrate all options properly", function()
    assert.are.same({
      "New config field `filesystem.filtered_items` already exists, please remove the deprecated configuration at `filesystem.filters`",
      "The `filesystem.filters.show_hidden` option has been deprecated, please use `filesystem.filtered_items.hide_dotfiles` instead.",
      "The `filesystem.filters.respect_gitignore` option has been deprecated, please use `filesystem.filtered_items.hide_gitignored` instead.",
      "The `filesystem.filters.gitignore_source` option has been removed.",
      "The `filesystem.filtered_items.gitignore_source` option has been removed.",
      "The `filesystem.hijack_netrw_behavior=open_split` option has been renamed to `open_current`.",
      "The `filesystem.window.position=split` option has been renamed to `current`.",
      "The `buffers.window.position=split` option has been renamed to `current`.",
      "The `git_status.window.position=split` option has been renamed to `current`.",
      "The `filesystem.follow_current_file` option has been replaced with a table, please move to `filesystem.follow_current_file.enabled`.",
      "The `buffers.follow_current_file` option has been replaced with a table, please move to `buffers.follow_current_file.enabled`.",
      "The `close_floats_on_escape_key` option has been removed.",
      [[
The `enable_normal_mode_for_inputs` option has been removed.
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
]],
    }, deprecations.migrate(deprecated_config))
    assert.are.same({
      filesystem = {
        hijack_netrw_behavior = "open_current",
        filters = {
          gitignore_source = nil,
        },
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = true,
          gitignore_source = nil,
        },
        follow_current_file = {
          enabled = true,
        },
        window = {
          position = "current",
        },
      },
      buffers = {
        follow_current_file = {
          enabled = true,
        },
        window = {
          position = "current",
        },
      },
      git_status = {
        window = {
          position = "current",
        },
      },
      -- removed
      close_floats_on_escape_key = nil,
      -- removed
      enable_normal_mode_for_inputs = nil,
    }, deprecated_config)
  end)
end)
