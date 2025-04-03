if vim.g.loaded_neo_tree == 1 or vim.g.loaded_neo_tree == true then
  return
end

-- Possibly convert this to lua using customlist instead of custom in the future?
vim.api.nvim_create_user_command("Neotree", function(ctx)
  require("neo-tree.command")._command(unpack(ctx.fargs))
end, {
  nargs = "*",
  complete = "custom,v:lua.require'neo-tree.command'.complete_args",
})

---@param path string? The path to check
---@return boolean hijacked Whether we hijacked a buffer
local function try_netrw_hijack(path)
  if not path or #path == 0 then
    return false
  end

  local stats = (vim.uv or vim.loop).fs_stat(path)
  if not stats or stats.type ~= "directory" then
    return false
  end

  return require("neo-tree.setup.netrw").hijack()
end

local augroup = vim.api.nvim_create_augroup("NeoTree_NetrwDeferred", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter" }, {
  group = augroup,
  callback = function(args)
    return vim.g.neotree_watching_bufenter == 1 or try_netrw_hijack(args.file)
  end,
})

vim.g.loaded_neo_tree = 1
