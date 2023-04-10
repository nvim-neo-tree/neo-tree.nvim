---Filter lsp clients response
local utils = require("neo-tree.utils")

local M = {
  filter_resp = function()
    return {}
  end,
}

local filter_clients = function(filter_type, filter_fn, resp)
  if resp == nil or type(resp) ~= "table" then
    return {}
  end
  filter_fn = filter_fn or function(client_name)
    return true
  end

  local result = {}
  for client_id, client_resp in pairs(resp) do
    local client_name = vim.lsp.get_client_by_id(client_id).name
    if filter_fn(client_name) and client_resp.result ~= nil then
      result[client_name] = client_resp.result
      if filter_type ~= "all" then
        break
      end
    end
  end
  return result
end

local white_list = function(white_list)
  return function(client_name)
    return vim.tbl_contains(white_list, client_name)
  end
end

local black_list = function(black_list)
  return function(client_name)
    return not vim.tbl_contains(black_list, client_name)
  end
end

M.setup = function(cfg_flt)
  local filter_type = "first"
  local filter_fn = nil

  if type(cfg_flt) == "table" then
    if cfg_flt.type == "all" then
      filter_type = "all"
    end

    if cfg_flt.fn ~= nil then
      filter_fn = cfg_flt.fn
    elseif cfg_flt.white_list then
      filter_fn = white_list(cfg_flt.white_list)
    elseif cfg_flt.black_list then
      filter_fn = black_list(cfg_flt.black_list)
    end
  elseif cfg_flt == "all" then
    filter_type = "all"
  end

  M.filter_resp = function(resp)
    return filter_clients(filter_type, filter_fn, resp)
  end
end

return M
