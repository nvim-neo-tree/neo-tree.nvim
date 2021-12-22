local vim = vim
local fs = require('neo-tree.sources.filesystem')

local commands = {}

commands.open = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'directory' then
    fs.toggle_directory()
  else
    if state.window.position == "right" then
      vim.cmd("wincmd t")
    else
      vim.cmd("wincmd w")
    end
    vim.cmd("e " .. node.id)
  end
end

commands.refresh = fs.refresh

commands.search = fs.search

commands.set_root = function(state)
  local tree = state.tree
  local node = tree:get_node()
  if node.type == 'directory' then
    fs.navigate(node.id)
  end
end

commands.toggle_hidden = fs.toggle_hidden

commands.toggle_gitignore = fs.toggle_gitignore

commands.up = fs.navigate_up

return commands
