local u = require("tests.utils")
local verify = require("tests.utils.verify")

describe("Clipboard sync", function()
  local test = u.fs.init_test({
    items = {
      {
        name = "foo",
        type = "dir",
        items = {
          {
            name = "bar",
            type = "dir",
            items = {
              { name = "baz1.txt", type = "file" },
              { name = "baz2.txt", type = "file", id = "deepfile2" },
            },
          },
          { name = "foofile1.txt", type = "file" },
        },
      },
      { name = "topfile1.txt", type = "file", id = "topfile1" },
    },
  })

  test.setup()

  after_each(function()
    u.clear_environment()
  end)

  describe("Global", function()
    it("should sync copying and clearing across tabs", function()
      require("neo-tree").setup({
        clipboard = {
          sync = "global",
        },
      })

      vim.cmd("Neotree")
      u.wait_for_neo_tree()
      local state = assert(verify.get_state())
      local first_win = vim.api.nvim_get_current_win()

      vim.cmd("tabnew")
      vim.cmd("Neotree")
      u.wait_for_neo_tree()
      local other_state = assert(verify.get_state())
      assert(not next(other_state.clipboard))

      vim.api.nvim_set_current_win(first_win)
      local wait1 = u.changedtick_waiter()
      u.feedkeys("y")
      wait1()
      assert(next(state.clipboard))
      verify.eventually(function()
        return next(other_state.clipboard) ~= nil
      end, "copy was not synchronized to the existing tab")
      u.eq(state.clipboard, other_state.clipboard)

      vim.cmd("tabnew")
      vim.cmd("Neotree")
      u.wait_for_neo_tree()
      local new_state = assert(verify.get_state())
      u.eq(state.clipboard, new_state.clipboard)

      require("neo-tree.sources.common.commands").clear_clipboard(new_state)
      assert(not next(new_state.clipboard))
      verify.eventually(function()
        return not next(state.clipboard) and not next(other_state.clipboard)
      end, "clear was not synchronized to the existing tabs")
    end)
  end)

  test.teardown()
end)
