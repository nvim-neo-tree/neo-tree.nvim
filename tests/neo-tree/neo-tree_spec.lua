local util = require("tests.helpers.util")
local verify = require("tests.helpers.verify")

describe("Filesystem source command", function()
  local fs = util.setup_test_fs()

  after_each(function()
    util.clear_test_state()
  end)

  it("should reveal the current file in the tree", function()
    local testfile = fs.content[3].abspath
    util.editfile(testfile)

    local start_bufnr = vim.api.nvim_get_current_buf()

    vim.cmd("NeoTreeReveal")
    verify.bufnr_is_not(start_bufnr)
    verify.tree_focused()
    verify.tree_node_is(testfile)
  end)

  it("should toggle the reveal-state of the tree", function()
    local testfile = fs.content[3].abspath
    util.editfile(testfile)

    local start_bufnr = vim.api.nvim_get_current_buf()

    vim.cmd("NeoTreeRevealToggle")
    verify.bufnr_is_not(start_bufnr)
    verify.tree_focused()
    verify.tree_node_is(testfile)

    -- Wait long enough such that the tree _should have_ closed, then assert it is not focused anymore
    vim.cmd("NeoTreeRevealToggle")
    verify.after(250, function()
      return #vim.api.nvim_tabpage_list_wins(0) == 1
        and start_bufnr == vim.api.nvim_get_current_buf()
    end, "Failed to toggle the tree to a closed state with 'action=reveal'")
  end)

  util.teardown_test_fs()
end)
