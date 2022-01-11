local Action = require("neo-tree.utils.command.action")

describe("Command action", function()
  it("should add arguments to the 'show' action by default", function()
    local action = Action:new("show", {})

    assert.are.same(action:make_opts(), { no_focus = true, close_others = true })
  end)

  it("should not add values if the action has nothing in 'map'", function()
    local action = Action:new("foo", {})

    assert.are.same(action:make_opts(), {})
  end)
end)
