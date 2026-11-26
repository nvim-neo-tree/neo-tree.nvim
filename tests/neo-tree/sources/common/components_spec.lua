pcall(require, "luacov")

local components = require("neo-tree.sources.common.components")
local git = require("neo-tree.git")
local highlights = require("neo-tree.ui.highlights")

describe("sources/common/components git_status", function()
  local original_find_existing_status_code

  before_each(function()
    original_find_existing_status_code = git.find_existing_status_code
  end)

  after_each(function()
    git.find_existing_status_code = original_find_existing_status_code
  end)

  it("shows one change marker and one conflict marker for conflicted file nodes", function()
    git.find_existing_status_code = function()
      return "UU"
    end

    local rendered = components.git_status({
      symbols = {
        modified = "M",
        conflict = "C",
      },
    }, {
      type = "file",
      path = "/tmp/conflicted.rs",
    }, {
      git_base_by_worktree = {},
    })

    assert.are.same({
      {
        text = "M ",
        highlight = highlights.GIT_MODIFIED,
      },
      {
        text = "C ",
        highlight = highlights.GIT_CONFLICT,
      },
    }, rendered)
  end)
end)

describe("sources/common/components name show_sort_icon", function()
  local commands = require("neo-tree.sources.common.commands")
  local manager = require("neo-tree.sources.manager")

  local function make_root_node()
    return {
      name = "project",
      type = "directory",
      path = "/tmp/project",
      get_depth = function()
        return 1
      end,
    }
  end

  local function make_state(sort)
    return {
      name = "filesystem",
      current_position = "current",
      sort = sort,
      components = components,
    }
  end

  it("shows the sort icon by default when sorting by Name in current position", function()
    local rendered =
      components.name({}, make_root_node(), make_state({ label = "Name", direction = 1 }))
    assert.are.same("project  ▲", rendered.text)

    rendered = components.name(
      { show_sort_icon = true },
      make_root_node(),
      make_state({ label = "Name", direction = -1 })
    )
    assert.are.same("project  ▼", rendered.text)
  end)

  it("never shows the sort icon when show_sort_icon is false", function()
    local rendered = components.name(
      { show_sort_icon = false },
      make_root_node(),
      make_state({ label = "Name", direction = 1, explicit = true })
    )
    assert.are.same("project", rendered.text)

    rendered = components.name(
      { show_sort_icon = false },
      make_root_node(),
      make_state({ label = "Name", direction = -1, explicit = true })
    )
    assert.are.same("project", rendered.text)
  end)

  it(
    "only shows the sort icon after an explicit sort command when show_sort_icon is 'after_sort'",
    function()
      local u = require("tests.utils")
      local nt = require("neo-tree")
      nt.setup({
        default_component_configs = {
          name = {
            show_sort_icon = "after_sort",
          },
        },
      })
      nt.ensure_config()
      local original_refresh = manager.refresh
      manager.refresh = function() end
      local ok, err = pcall(function()
        local state = make_state({ label = "Name", direction = 1 })
        local name_cfg = nt.config.default_component_configs.name
        local initial = components.name(name_cfg, make_root_node(), state)
        assert.are.same("project", initial.text)

        commands.order_by_name(state)
        local after_first = components.name(name_cfg, make_root_node(), state)
        assert.are.same("project  ▼", after_first.text)

        commands.order_by_name(state)
        local after_second = components.name(name_cfg, make_root_node(), state)
        assert.are.same("project  ▲", after_second.text)
      end)
      manager.refresh = original_refresh
      u.clear_environment()
      assert.is_true(ok, err)
    end
  )

  it(
    "only shows the sort icon when sorting descending when show_sort_icon is 'descending'",
    function()
      local asc = components.name(
        { show_sort_icon = "descending" },
        make_root_node(),
        make_state({ label = "Name", direction = 1 })
      )
      assert.are.same("project", asc.text)

      local desc = components.name(
        { show_sort_icon = "descending" },
        make_root_node(),
        make_state({ label = "Name", direction = -1 })
      )
      assert.are.same("project  ▼", desc.text)
    end
  )
end)
