local u = require("tests.utils")
local verify = require("tests.utils.verify")
describe("Neo-tree should be able to track previous windows", function()
  -- Just make sure we start all tests in the expected state
  before_each(function()
    u.eq(1, #vim.api.nvim_list_wins())
    u.eq(1, #vim.api.nvim_list_tabpages())
  end)

  after_each(function()
    u.clear_environment()
  end)

  it("before opening", function()
    vim.cmd.vsplit()
    vim.cmd.split()
    vim.cmd.wincmd("l")
    local win = vim.api.nvim_get_current_win()
    verify.schedule(function()
      local prior_windows =
        require("neo-tree.utils").prior_windows[vim.api.nvim_get_current_tabpage()]
      return assert.are.same(win, prior_windows[#prior_windows])
    end)
  end)
end)
