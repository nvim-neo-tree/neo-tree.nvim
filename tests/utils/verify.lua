local utils = require("neo-tree.utils")
local verify = {}
---@alias neotree.test.assertfunc fun(...):success: any, err: string?
---@alias neotree.test.failmsg (fun():string)|string

local DEFAULT_TIMEOUT = 1000
---@param failmsg neotree.test.failmsg
---@return string
local resolve_failmsg = function(failmsg)
  if type(failmsg) == "function" then
    return failmsg()
  end
  return failmsg
end
---@param assertfunc neotree.test.assertfunc
---@param failmsg neotree.test.failmsg
---@param timeout integer?
verify.eventually = function(assertfunc, failmsg, timeout, ...)
  local args = { ... }
  local success, last_err
  ---@type boolean, boolean|-1|-2|nil
  local notimeout = vim.wait(timeout or DEFAULT_TIMEOUT, function()
    success, last_err = assertfunc(unpack(args))
    return success, last_err
  end)
  local err = resolve_failmsg(last_err or failmsg)
  if not notimeout then
    err = "timeout: " .. err
  end
  assert(notimeout and success, err)
end

---Blocks until the assertfunc is run on the next vim.schedule. Will throw the error thrown by the scheduled function.
---@param assertfunc neotree.test.assertfunc
---@param timeout integer?
verify.schedule = function(assertfunc, timeout)
  local scheduled_func_ran = false
  local ok, err = false, nil
  vim.schedule(function()
    ok, err = pcall(assertfunc)
    scheduled_func_ran = true
  end)
  local notimeout = vim.wait(timeout or DEFAULT_TIMEOUT, function()
    return scheduled_func_ran
  end)
  assert(notimeout and ok, err)
end

verify.after = function(timeout, assertfunc, failmsg)
  vim.wait(timeout)
  assert(assertfunc(), failmsg)
end

verify.bufnr_is = function(bufnr, timeout)
  verify.eventually(function()
    return bufnr == vim.api.nvim_get_current_buf()
  end, string.format("Current buffer is expected to be '%s' but is not", bufnr), timeout)
end

verify.bufnr_is_not = function(bufnr, timeout)
  verify.eventually(function()
    return bufnr ~= vim.api.nvim_get_current_buf()
  end, string.format("Current buffer is '%s' when expected to not be", bufnr), timeout)
end

verify.buf_name_endswith = function(buf_name, timeout)
  verify.eventually(
    function()
      if buf_name == "" then
        return true
      end
      local n = vim.api.nvim_buf_get_name(0)
      if n:sub(-#buf_name) == buf_name then
        return true
      else
        return false
      end
    end,
    string.format("Current buffer name is expected to be end with '%s' but it does not", buf_name),
    timeout
  )
end

--TODO: revisit whether the tests this function allows through should actually require hard equality of paths (down to
--perfect normalization).
local path_equal = function(a, b)
  if utils.is_windows and utils.windowize_path(a) == utils.windowize_path(b) then
    return true
  end
  return a == b
end

---@param timeout integer?
verify.buf_name_is = function(buf_name, timeout)
  verify.eventually(function()
    return path_equal(buf_name, vim.api.nvim_buf_get_name(0))
  end, function()
    local _, err = pcall(assert.are.equal, buf_name, vim.api.nvim_buf_get_name(0))
    return err
  end, timeout)
end

---@param timeout integer?
verify.tree_focused = function(timeout)
  verify.eventually(function()
    if not verify.get_state() then
      return false
    end
    return vim.bo[0].filetype == "neo-tree"
  end, "Current buffer is not a 'neo-tree' filetype", timeout)
end

---@param source_name string?
---@param winid integer?
verify.get_state = function(source_name, winid)
  if source_name == nil then
    local success
    success, source_name = pcall(vim.api.nvim_buf_get_var, 0, "neo_tree_source")
    if not success then
      return nil
    end
  end
  local state = require("neo-tree.sources.manager").get_state(source_name, nil, winid)
  if not state.tree then
    return nil
  end
  if not state._ready then
    return nil
  end
  return state
end

verify.tree_node_is = function(source_name, expected_node_id, winid, timeout)
  verify.eventually(function()
    local state = verify.get_state(source_name, winid)
    if not state then
      return false
    end
    local success, node = pcall(state.tree.get_node, state.tree)
    if not success then
      return false
    end
    if not node then
      return false
    end
    local node_id = node:get_id()
    return path_equal(node_id, expected_node_id)
  end, function()
    local state = assert(verify.get_state(source_name, winid))
    local node = assert(state.tree.get_node(state.tree))
    local node_id = node:get_id()
    local ok, err = pcall(assert.are.equal, expected_node_id, node_id)
    return err
  end, timeout)
end

verify.filesystem_tree_node_is = function(expected_node_id, winid, timeout)
  verify.tree_node_is("filesystem", expected_node_id, winid, timeout)
end

verify.buffers_tree_node_is = function(expected_node_id, winid, timeout)
  verify.tree_node_is("buffers", expected_node_id, winid, timeout)
end

verify.git_status_tree_node_is = function(expected_node_id, winid, timeout)
  verify.tree_node_is("git_status", expected_node_id, winid, timeout)
end

verify.window_handle_is = function(winid, timeout)
  verify.eventually(function()
    return winid == vim.api.nvim_get_current_win()
  end, string.format("Current window handle is expected to be '%s' but is not", winid), timeout)
end

verify.window_handle_is_not = function(winid, timeout)
  verify.eventually(function()
    return winid ~= vim.api.nvim_get_current_win()
  end, string.format("Current window handle is not expected to be '%s' but it is", winid), timeout)
end

return verify
