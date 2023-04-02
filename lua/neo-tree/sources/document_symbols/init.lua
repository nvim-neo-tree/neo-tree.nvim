--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")

local M = { name = "document_symbols" }

local get_state = function()
  return manager.get_state(M.name)
end

local function dfs(resp_node, id)
  local children = {}
  for i, child in ipairs(resp_node.children or {}) do
    -- print("children of", resp_node.name, ":", child.name)
    local child_node = dfs(child, id .. "." .. i)
    -- print("children of", resp_node.name, ":", vim.inspect(child_node))
    table.insert(children, child_node)
  end
  -- print("children of", resp_node.name, ":", vim.inspect(children))
  local symb_node = {
    id = id,
    name = resp_node.name,
    type = "directory",
    kind = resp_node.kind,
    children = children,
  }
  -- print(resp_node.name)
  return symb_node
end

local on_lsp_resp = function(resp, bufname, state)
  -- print(vim.inspect(resp))
  if resp == nil or type(resp) ~= "table" then
    return
  end
  local symbol_list = {}
  for _, client_result in pairs(resp) do
    client_result = client_result.result
    if client_result == nil then
      return
    end

    for i, resp_node in ipairs(client_result) do
      -- print(vim.inspect(resp_node))
      table.insert(symbol_list, dfs(resp_node, "1." .. i))
    end
    -- Do something useful here to get items
    local items = {
      {
        id = "1",
        name = bufname,
        type = "directory",
        children = symbol_list,
      },
    }
    print(vim.inspect(items))
    renderer.show_nodes(items, state)
  end
end
---Navigate to the given path.
M.navigate = function(state)
  local winid, is_neo_tree = utils.get_appropriate_window(state)
  local buf = vim.api.nvim_win_get_buf(winid)
  local bufname = vim.api.nvim_buf_get_name(buf)
  local symbols = vim.lsp.buf_request_all(
    buf,
    "textDocument/documentSymbol",
    { textDocument = vim.lsp.util.make_text_document_params(buf) },
    function(resp)
      on_lsp_resp(resp, bufname, state)
    end
  )
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  get_state()
  -- You most likely want to use this function to subscribe to events
  if config.use_libuv_file_watcher then
    manager.subscribe(M.name, {
      event = events.FS_EVENT,
      handler = function(args)
        manager.refresh(M.name)
      end,
    })
  end
end

return M
