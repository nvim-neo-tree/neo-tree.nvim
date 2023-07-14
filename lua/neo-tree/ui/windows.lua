local locations = {}

local get_location = function(location)
  local tab = vim.api.nvim_get_current_tabpage()
  if not locations[tab] then
    locations[tab] = {}
  end
  local loc = locations[tab][location]
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
  locations[tab][location] = loc
  return loc
end

return { get_location = get_location }
