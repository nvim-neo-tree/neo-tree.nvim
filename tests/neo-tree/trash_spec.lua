local u = require("tests.utils")
describe("config.trash.command", function()
  -- Just make sure we start all tests in the expected state
  after_each(function()
    u.clear_environment()
  end)

  it("accepts nil values from function commands", function()
    local triggered = false
    require("neo-tree").setup({
      trash = {
        command = function()
          triggered = true
          return nil
        end,
      },
    })

    require("neo-tree.trash").trash({ "example" })
    assert.are.equal(triggered, true, "Was not triggered")
  end)

  it("works with functions that return functions", function()
    local triggered = false
    require("neo-tree").setup({
      trash = {
        command = function()
          return function()
            triggered = true
            return true
          end
        end,
      },
    })

    require("neo-tree.trash").trash({ "example" })
    assert.are.equal(triggered, true, "Was not triggered")
  end)
end)
