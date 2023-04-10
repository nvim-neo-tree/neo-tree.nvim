--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local highlights = require("neo-tree.ui.highlights")
local filters = require("neo-tree.sources.document_symbols.lib.client_filters")
local kinds = require("neo-tree.sources.document_symbols.lib.kinds")

local M = { name = "document_symbols" }

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
      kind = kinds.get_kind(resp_node.kind),
      -- range = parse_range(resp_node.range, 1, 0),
      selection_range = parse_range(resp_node.selectionRange, 1, 0),
      detail = resp_node.detail,
      position = preview_range.start,
      end_position = preview_range["end"],
    },
  }
  return symb_node
end

---Callback function for lsp request
---@param resp table the response of the lsp client
---@param state table the state of the source
local on_lsp_resp = function(resp, state)
  if resp == nil or type(resp) ~= "table" then
    return
  end

  resp = filters.filter_resp(resp)

  local items = {}
  for client_name, client_result in pairs(resp) do
    local symbol_list = {}
    for i, resp_node in ipairs(client_result) do
      table.insert(symbol_list, dfs(resp_node, #items .. "." .. i, state))
    end

    local splits = vim.split(state.path, "/")
    local filename = splits[#splits]

    table.insert(items, {
      id = "" .. #items,
      name = string.format("SYMBOLS (%s) in %s", client_name, filename),
      path = state.path,
      type = "root",
      children = symbol_list,
      extra = { kind = { name = "Root", icon = "", hl = highlights.ROOT_NAME } },
    })
  end
  renderer.show_nodes(items, state)
end

---Navigate to the given path.
M.navigate = function(state)
  local winid, _ = utils.get_appropriate_window(state)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local bufname = vim.api.nvim_buf_get_name(bufnr)

  -- if no client found, terminate
  local client_found = false
  for _, client in pairs(vim.lsp.get_active_clients({ bufnr = bufnr })) do
    if client.server_capabilities.documentSymbolProvider then
      client_found = true
      break
    end
  end
  if not client_found then
    local splits = vim.split(bufname, "/")
    renderer.show_nodes({
      {
        id = "0",
        name = "No client found for " .. splits[#splits],
        path = bufname,
        type = "root",
        children = {},
        extra = { kind = { name = "Root", icon = "!", hl = highlights.ROOT_NAME } },
      },
    }, state)
    return
  end

  -- client found
  state.lsp_winid = winid
  state.lsp_bufnr = bufnr
  state.path = vim.api.nvim_buf_get_name(bufnr)

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
  filters.setup(config.client_filters)
  kinds.setup(config.custom_kinds, config.kinds)

  if config.before_render then
    --convert to new event system
    manager.subscribe(M.name, {
      event = events.BEFORE_RENDER,
      handler = function(state)
        local this_state = get_state()
        if state == this_state then
          config.before_render(this_state)
        end
      end,
    })
  end

  manager.subscribe(M.name, {
    event = events.VIM_BUFFER_ENTER,
    handler = function()
      manager.refresh(M.name)
    end,
  })
  manager.subscribe(M.name, {
    event = events.VIM_INSERT_LEAVE,
    handler = function()
      manager.refresh(M.name)
    end,
  })
  manager.subscribe(M.name, {
    event = events.VIM_TEXT_CHANGED_NORMAL,
    handler = function()
      manager.refresh(M.name)
    end,
  })
end

return M
