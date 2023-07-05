local locations = {}

local get_location = function(location)
  local loc = locations[location]
  if loc then
    if loc.winid ~= 0 then
      -- verify the window before we return it
      if not vim.api.nvim_win_is_valid(loc.winid) then
        loc.winid = 0
      end
    end
    return loc
  end
  loc = {
    source = nil,
    name = location,
    winid = 0,
  }
  locations[location] = loc
  return loc
end

local M = { get_location = get_location }
return M
