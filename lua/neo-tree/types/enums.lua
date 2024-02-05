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

---@enum NeotreeWindowPosition
M.valid_window_positions = {
  left = "left",
  right = "right",
  top = "top",
  bottom = "bottom",
  float = "float",
  current = "current",
}

return M
