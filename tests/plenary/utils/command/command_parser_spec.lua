local CommandParser = require("neo-tree.utils.command.parser")

local function makeargs(t)
  return { unpack(t) }
end

describe("Command parser", function()
  it("should split arguments based on multiple whitespace tokens", function()
    local parser = CommandParser:new(makeargs({ "foo", "bar" }))
    local parsed = parser:parse()

    assert.are.same(parsed, { args = { "foo", "bar" }, kwargs = {} })
  end)

  it("should split positional arguments and keyword arguments separately", function()
    local parser = CommandParser:new(makeargs({ "foo", "bar=baz" }))
    local parsed = parser:parse()

    assert.are.same(parsed, { args = { "foo" }, kwargs = { bar = "baz" } })
  end)
end)
