if vim.g.loaded_neo_tree == 1 or vim.g.loaded_neo_tree == true then
  return
end

vim.api.nvim_create_user_command("Neotree", function(ctx)
  require("neo-tree.command")._command(unpack(ctx.fargs))
end, {
  nargs = "*",
  complete = function(argLead, cmdLine)
    require("neo-tree.command").complete_args(argLead, cmdLine)
  end,
})

---@param path string? The path to check
---@return boolean hijacked Whether the hijack worked
local function try_netrw_hijack(path)
  if not path or #path == 0 then
    return false
  end

  local netrw = require("neo-tree.setup.netrw")
  if netrw.get_hijack_behavior() ~= "disabled" then
    vim.cmd("silent! autocmd! FileExplorer *")
    local stats = (vim.uv or vim.loop).fs_stat(path)
    if stats and stats.type == "directory" then
      return netrw.hijack()
    end
  end
  return false
end

-- currently need to check first arg to not break hijacked on
-- configs that already lazy-load neo-tree (e.g. lazyvim)
local first_arg = vim.fn.argv(0) --[[@as string]]
if not try_netrw_hijack(first_arg) then
  local augroup = vim.api.nvim_create_augroup("NeoTree_NetrwDeferred", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      if try_netrw_hijack(args.file) then
        vim.api.nvim_del_augroup_by_id(augroup)
      end
    end,
  })
end

vim.g.loaded_neo_tree = 1
