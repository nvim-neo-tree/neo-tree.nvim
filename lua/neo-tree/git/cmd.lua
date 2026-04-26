local M = {}

---@class neotree.git.cmd.Opts
---@field literal_pathspecs boolean?

---Returns a git command, argv-style, with sane defaults for parsing usage.
---opts.literal_pathspecs exists because some commands do not like the options (i.e. check-ignore). It is enabled by default.
---@param args string[]
---@param opts neotree.git.cmd.Opts?
---@return string[]
M.with_args = function(args, opts)
  opts = opts or {}
  local command = {
    "git",
    "--no-pager",
    "--no-optional-locks",
    "-c",
    "gc.auto=0",
    "-c",
    "core.quotepath=off",
    "-c",
    "color.ui=false",
    "-c",
    "color.diff=false",
  }
  if opts.literal_pathspecs ~= false then
    command[#command + 1] = "--literal-pathspecs"
  end
  return vim.list_extend(command, args)
end

return M
