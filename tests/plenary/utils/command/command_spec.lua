local stub = require("luassert.stub")

local Action = require("neo-tree.utils.command.action")
local CommandParser = require("neo-tree.utils.command.parser")
local NeoTree = require("neo-tree")
local command = require("neo-tree.utils.command")

describe("Command", function()
  local default_action = "float"

  before_each(function()
    stub(NeoTree, "get_sources")
    stub(NeoTree, default_action)
    NeoTree.get_sources.returns({ "filesystem", "buffers" })

    stub(CommandParser, "new")
    stub(CommandParser, "parse")
    CommandParser.new.returns(CommandParser)

    stub(Action, "new")
    stub(Action, "make_opts")
    Action.new.returns(Action)
    Action.make_opts.returns("mock_opts")
    Action.name = default_action
  end)

  after_each(function()
    NeoTree.get_sources:revert()

    CommandParser.new:revert()
    CommandParser.parse:revert()

    Action.new:revert()
    Action.make_opts:revert()
    Action.name = nil
  end)

  it("should error if the source is invalid", function()
    CommandParser.parse.returns({ args = { "foo" }, kwargs = {} })

    assert.has_error(command.run, "Invalid NeoTree source 'foo'")
    assert.stub(CommandParser.parse).was.called(1)
    assert.stub(Action.new).was_not.called()
  end)

  it("should error if the action is empty", function()
    CommandParser.parse.returns({ args = { "filesystem" }, kwargs = {} })

    assert.has_error(command.run, "Invalid NeoTree action 'nil'")
    assert.stub(CommandParser.parse).was.called(1)
    assert.stub(Action.new).was_not.called()
  end)

  it("should error if the action is not a valid NeoTree function", function()
    CommandParser.parse.returns({ args = { "filesystem" }, kwargs = { action = "noitcnuf" } })

    assert.has_error(command.run, "Invalid NeoTree action 'noitcnuf'")
    assert.stub(CommandParser.parse).was.called(1)
    assert.stub(Action.new).was_not.called()
  end)

  it("should error if the action is not a valid NeoTree function", function()
    CommandParser.parse.returns({ args = { "filesystem" }, kwargs = { action = "noitcnuf" } })

    assert.has_error(command.run, "Invalid NeoTree action 'noitcnuf'")
    assert.stub(CommandParser.parse).was.called(1)
    assert.stub(Action.new).was_not.called()
  end)

  it("should create a new action object based on the parsed command", function()
    local parsed = { args = { "filesystem" }, kwargs = { action = default_action } }
    CommandParser.parse.returns(parsed)

    assert.has_no.errors(command.run)

    assert.stub(Action.new).was.called_with(Action, parsed.kwargs.action, parsed.kwargs)
    assert.stub(NeoTree[default_action]).was.called_with(unpack(parsed.args), "mock_opts")
  end)
end)
