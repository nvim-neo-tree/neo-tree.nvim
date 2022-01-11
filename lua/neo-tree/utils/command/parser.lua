local CommandParser = {}

function CommandParser:new(args)
  local o = {}

  setmetatable(o, self)
  self.__index = self

  o._raw = args

  return o
end

function CommandParser:parse()
  local parsed = {
    args = {},
    kwargs = {},
  }

  for _, token in ipairs(self._raw) do
    local kv = vim.split(token, "=")

    if #kv > 1 then
      parsed.kwargs[kv[1]] = kv[2]
    else
      table.insert(parsed.args, kv[1])
    end
  end

  return parsed
end

return CommandParser
