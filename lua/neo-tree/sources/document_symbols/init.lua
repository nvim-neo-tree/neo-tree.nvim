--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local highlights = require("neo-tree.ui.highlights")
local filters = require("neo-tree.sources.document_symbols.lib.server_filters")

local M = { name = "document_symbols" }
M.server_filter = filters.parse_server_filter()
M.get_kind = function()
  return { name = "", icon = " ", hl = "" }
end

local get_state = function()
  return manager.get_state(M.name)
end

---Parse the LspRange
---@param range table the LspRange object to parse
---@param row_offset integer the offset for line (e.g for nvim_set_cursor() this is 1)
---@param col_offset integer the offset for column
---@return table range the parsed range
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

---Parse the LSP response into a tree
---@param resp_node table the LSP response node
---@param id string the id of the current node
---@return table symb_node the parsed tree
local function dfs(resp_node, id, state)
  -- parse all children
  local children = {}
  for i, child in ipairs(resp_node.children or {}) do
    local child_node = dfs(child, id .. "." .. i, state)
    table.insert(children, child_node)
  end

  -- parse current node
  local preview_range = parse_range(resp_node.range, 0, 0) -- for commands.preview
  local symb_node = {
    id = id,
    name = resp_node.name,
    type = "symbol",
    path = state.path,
    children = children,
    extra = {
      bufnr = state.lsp_bufnr,
      kind = M.get_kind(resp_node.kind),
      range = parse_range(resp_node.range, 1, 0),
      selection_range = parse_range(resp_node.selectionRange, 1, 0),
      detail = resp_node.detail,
      position = preview_range.start,
      end_position = preview_range["end"],
    },
  }
  return symb_node
end

---Callback function for lsp request
---@param resp table the response of the lsp server
---@param state table the state of the source
local on_lsp_resp = function(resp, state)
  if resp == nil or type(resp) ~= "table" then
    return
  end

  resp = M.server_filter(resp)

  local symbol_list = {}
  local items = {}
  local id = 0
  for client_name, client_result in pairs(resp) do
    for i, resp_node in ipairs(client_result) do
      table.insert(symbol_list, dfs(resp_node, id .. "." .. i, state))
    end

    local filename = vim.split(state.path, "/")
    filename = filename[#filename]

    table.insert(items, {
      id = "" .. id,
      name = string.format("(%s) in %s", client_name, filename),
      path = state.path,
      type = "root",
      children = symbol_list,
      extra = { kind = { name = "Root", icon = "", hl = highlights.ROOT_NAME } },
    })
    id = id + 1
  end
  renderer.show_nodes(items, state)
  state.loading = false
end

---Navigate to the given path.
M.navigate = function(state)
  if state.loading then
    return
  end
  state.loading = true
  local winid, is_neo_tree = utils.get_appropriate_window(state)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  state.lsp_winid = winid
  state.lsp_bufnr = bufnr
  state.path = bufname

  vim.lsp.buf_request_all(
    bufnr,
    "textDocument/documentSymbol",
    { textDocument = vim.lsp.util.make_text_document_params(bufnr) },
    function(resp)
      on_lsp_resp(resp, state)
    end
  )
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
---wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  M.server_filter = filters.parse_server_filter(config.server_filter)
  M.get_kind = function(kind_id)
    return config.kinds[kind_id] or { name = "Unknown", icon = "?", hl = "" }
  end
  manager.subscribe(M.name, {
    event = events.VIM_LSP_REQUEST,
    handler = function(args)
      manager.refresh(M.name)
    end,
  })
end

return M
