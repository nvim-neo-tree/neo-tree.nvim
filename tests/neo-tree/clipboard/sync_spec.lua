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
    it("should work", function()
      require("neo-tree").setup({
        clipboard = {
          sync = "global",
        },
      })

      vim.cmd("Neotree")
      u.wait_for_neo_tree()
      local state = assert(verify.get_state())
      local wait1 = u.changedtick_waiter()
      u.feedkeys("y")
      wait1()
      assert(next(state.clipboard))

      vim.cmd("tabnew")
      vim.cmd("Neotree")
      u.wait_for_neo_tree()
      local other_state = assert(verify.get_state())
      assert(next(other_state.clipboard))
      local wait2 = u.changedtick_waiter(0, 1)
      u.feedkeys("y")
      wait2()
      assert(not next(other_state.clipboard))
    end)
  end)

  test.teardown()
end)
