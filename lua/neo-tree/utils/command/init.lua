local Action = require("neo-tree.utils.command.action")
local CommandParser = require("neo-tree.utils.command.parser")
local NeoTree = require("neo-tree")

local command = {}

local function validate_args(parsed)
  local source = parsed.args[1] or "current"

  if source ~= "current" and not vim.tbl_contains(NeoTree.get_sources(), source) then
    error("Invalid NeoTree source '" .. source .. "'")
  end

  local action = parsed.kwargs.action
  if not action or not NeoTree[action] then
    error("Invalid NeoTree action '" .. (action or "nil") .. "'")
  end

  return true
end

command.run = function(...)
  local parsed = CommandParser:new({ ... }):parse()

  local ok, _ = validate_args(parsed)
  if not ok then
    return
  end

  local action = Action:new(parsed.kwargs.action, parsed.kwargs)

  NeoTree[action.name](unpack(parsed.args), action:make_opts())
end

return command
