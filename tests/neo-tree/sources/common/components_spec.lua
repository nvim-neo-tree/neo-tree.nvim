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
