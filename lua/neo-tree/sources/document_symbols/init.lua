--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local kind = require("neo-tree.sources.document_symbols.lib.kind")
local highlights = require("neo-tree.ui.highlights")

local M = { name = "document_symbols" }

local get_state = function()
  return manager.get_state(M.name)
end

local parse_range = function(range, row_offset, col_offset)
  row_offset = row_offset or 0
  col_offset = col_offset or 0
  return {
    start = {
      range.start.line + row_offset,
      range.start.character + col_offset,
    },
    ["end"] = {
      range["end"].line + row_offset,
      range["end"].character + col_offset,
    },
  }
end

local function dfs(resp_node, id, bufnr, path)
  local children = {}
  for i, child in ipairs(resp_node.children or {}) do
    local child_node = dfs(child, id .. "." .. i, bufnr, path)
    table.insert(children, child_node)
  end
  local preview_range = parse_range(resp_node.range)
  local symb_node = {
    id = id,
    name = resp_node.name,
    type = "file",
    path = path,
    children = children,
    extra = {
      bufnr = bufnr,
      kind = kind.get_kind(resp_node.kind),
      range = parse_range(resp_node.range, 1),
      selection_range = parse_range(resp_node.selectionRange, 1),
      detail = resp_node.detail,
      position = preview_range.start,
      end_position = preview_range["end"],
    },
  }
  return symb_node
end

local on_lsp_resp = function(resp, bufname, state)
  if resp == nil or type(resp) ~= "table" then
    return
  end

  local symbol_list = {}
  for _, client_result in pairs(resp) do
    client_result = client_result.result
    if client_result ~= nil then
      for i, resp_node in ipairs(client_result) do
        table.insert(symbol_list, dfs(resp_node, "1." .. i, state.lsp_buf, bufname))
      end

      local items = {
        {
          id = "1",
          name = bufname,
          path = bufname,
          type = "directory",
          children = symbol_list,
          extra = { kind = { name = "Root", icon = "", hl = highlights.ROOT_NAME } },
        },
      }
      renderer.show_nodes(items, state)
      break
    end
  end
end

---Navigate to the given path.
M.navigate = function(state)
  local winid, is_neo_tree = utils.get_appropriate_window(state)
  local buf = vim.api.nvim_win_get_buf(winid)
  local bufname = vim.api.nvim_buf_get_name(buf)
  state.lsp_winid = winid
  state.lsp_buf = buf
  state.path = bufname -- so that M.refresh() works

  vim.lsp.buf_request_all(
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
  manager.subscribe(M.name, {
    event = events.VIM_LSP_REQUEST,
    handler = function(args)
      manager.refresh(M.name)
    end,
  })
end

return M
