local u = require("tests.utils")
local verify = require("tests.utils.verify")
describe("Opening buffers in neo-tree window", function()
  -- Just make sure we start all tests in the expected state
  before_each(function()
    u.eq(1, #vim.api.nvim_list_wins())
    u.eq(1, #vim.api.nvim_list_tabpages())
  end)

  after_each(function()
    u.clear_environment()
  end)

  local width = 33
  describe("should automatically redirect to other buffers", function()
    it("without changing our own width", function()
      require("neo-tree").setup({
        window = {
          width = width,
        },
      })
      vim.cmd("e test.txt")
      vim.cmd("Neotree")
      local neotree = vim.api.nvim_get_current_win()
      assert.are.equal(width, vim.api.nvim_win_get_width(neotree))

      vim.cmd("bnext")
      verify.schedule(function()
        return assert.are.equal(width, vim.api.nvim_win_get_width(neotree))
      end, nil, "width should remain 33")
    end)
  end)
end)
