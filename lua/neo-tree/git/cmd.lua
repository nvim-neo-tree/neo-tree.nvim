local M = {}

---@param args string[]
---@return string[]
M.with_args = function(args)
  -- From gitsigns
  return vim.list_extend({
    "git",
    "--no-pager",
    "--no-optional-locks",
    "--literal-pathspecs",
    "-c",
    "gc.auto=0",
    "-c",
    "core.quotepath=off",
    "-c",
    "color.ui=false",
    "-c",
    "color.diff=false",
  }, args)
end

return M
