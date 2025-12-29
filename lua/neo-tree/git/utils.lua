local log = require("neo-tree.log")
local uv = vim.uv or vim.loop
local M = {}

---@param git_args string[]
---@param on_exit fun(code: integer, stdout_chunks: string[], stderr_chunks: string[])
---@param cwd string?
M.git_job = function(git_args, on_exit, cwd)
  local stdout_chunks = {}
  local stderr_chunks = {}

  --- uv.spawn blocks for 2x longer than jobstart but jobstart replaces \001 with \n which isn't ideal for path
  --- correctness (since paths can technically have newlines).
  ---
  --- Switch to vim.system in v4.0
  local stdout = log.assert(uv.new_pipe())
  local stderr = log.assert(uv.new_pipe())
  uv.spawn("git", {
    args = git_args,
    hide = true,
    stdio = { nil, stdout, stderr },
    cwd = cwd,
  }, function(code, _)
    stdout:close()
    stdout:shutdown()
    stderr:close()
    stdout:shutdown()
    on_exit(code, stdout_chunks, stderr_chunks)
  end)

  stdout:read_start(function(err, data)
    log.assert(not err, err)
    if type(data) == "string" then
      stdout_chunks[#stdout_chunks + 1] = data
    end
  end)
  stdout:read_start(function(err, data)
    log.assert(not err, err)
    if type(data) == "string" then
      stdout_chunks[#stdout_chunks + 1] = data
    end
  end)
end

return M
