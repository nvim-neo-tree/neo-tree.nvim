local deprecations = require("neo-tree.setup.deprecations")
describe("deprecation module", function()
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
    assert.are.same({}, deprecations.migrate(deprecated_config))
    assert.are.same({}, deprecated_config)
  end)
end)
