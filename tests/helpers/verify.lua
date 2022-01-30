local verify = {}

verify.eventually = function(timeout, assertfunc, failmsg, ...)
  local success, args = false, { ... }
  vim.wait(timeout or 1000, function()
    success = assertfunc(unpack(args))
    return success
  end)
  assert(success, failmsg)
end

verify.after = function(timeout, assertfunc, failmsg)
  vim.wait(timeout, function()
    return false
  end)
  assert(assertfunc(), failmsg)
end

verify.bufnr_is_not = function(start_bufnr, timeout)
  verify.eventually(timeout or 500, function()
    return start_bufnr ~= vim.api.nvim_get_current_buf()
  end, string.format("Current buffer is '%s' when expected to not be", start_bufnr))
end

verify.tree_focused = function(timeout)
  verify.eventually(timeout or 1000, function()
    return vim.api.nvim_buf_get_option(0, "filetype") == "neo-tree"
  end, "Current buffer is not a 'neo-tree' filetype")
end

verify.tree_node_is = function(expected_node_id, timeout)
  verify.eventually(timeout or 500, function()
    local state = require("neo-tree.sources.manager").get_state("filesystem")
    local node = state.tree:get_node()
    if not node then
      return false
    end
    local node_id = node:get_id()
    if node_id ~= expected_node_id then
      return false
    end
    if state.position.node_id ~= expected_node_id then
      return false
    end
    return true
  end, string.format("Tree node '%s' not focused", expected_node_id))
end

return verify
