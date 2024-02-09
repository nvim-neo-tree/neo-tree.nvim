local M = {}

---@enum NeotreeBufVar
M.buf_vars = {
  neo_tree_position = "neo_tree_position",
  neo_tree_source = "neo_tree_source",
  neo_tree_tabid = "neo_tree_tabid",
  neo_tree_winid = "neo_tree_winid",
}

---@enum NeotreeWinVar
M.win_vars = {
  neo_tree_settings_applied = "neo_tree_settings_applied",
}

---@enum NeotreeWindowPositionSplit
M.valid_split_window_positions = {
  left = "left",
  right = "right",
  top = "top",
  bottom = "bottom",
}

---@enum NeotreeWindowPositionFloat
M.valid_float_window_positions = {
  float = "float",
}

---@enum NeotreeWindowPositionCurrent
M.valid_current_window_positions = {
  current = "current",
}

---@enum NeotreeWindowPosition
M.valid_window_positions = {
  left = "left",
  right = "right",
  top = "top",
  bottom = "bottom",
  float = "float",
  current = "current",
}

-- TODO: Test window_positions contains all valid_*_window_positions.

return M
