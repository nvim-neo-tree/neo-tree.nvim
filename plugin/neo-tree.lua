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

vim.g.loaded_neo_tree = 1
