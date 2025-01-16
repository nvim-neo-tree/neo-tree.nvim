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

---@return boolean hijacked whether the hijack worked
local function try_netrw_hijack()
  require("neo-tree").ensure_config()
  local netrw = require("neo-tree.setup.netrw")
  if netrw.get_hijack_behavior() ~= "disabled" then
    vim.cmd("silent! autocmd! FileExplorer *")
    return netrw.hijack()
  end
  return false
end

---@param path string The path to check1
---@return boolean is_directory Whether it's a directory
local is_directory = function(path)
  if not path or #path == 0 then
    return false
  end
  local stats = (vim.uv or vim.loop).fs_stat(path)
  return stats and stats.type == "directory" or false
end
if
  is_directory(vim.fn.argv(0) --[[@as string]])
then
  -- currently needed to work around configs that already lazy-load neo-tree (e.g. lazyvim)
  try_netrw_hijack()
else
  local augroup = vim.api.nvim_create_augroup("NeoTree_NetrwDeferred", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      if is_directory(args.file) then
        try_netrw_hijack()
        vim.api.nvim_del_augroup_by_id(augroup)
      end
    end,
  })
end

vim.g.loaded_neo_tree = 1
