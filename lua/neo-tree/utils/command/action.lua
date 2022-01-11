local Action = {
  map = {
    show = { no_focus = true, close_others = true },
  },
}

function Action:new(name, opts)
  P("new action!")
  local o = {}

  setmetatable(o, self)
  self.__index = self

  o.name = name
  o.opts = opts

  return o
end

function Action:make_opts()
  if Action.map[self.name] then
    self.opts = vim.tbl_extend("keep", self.opts, Action.map[self.name])
  end

  return self.opts
end

return Action
