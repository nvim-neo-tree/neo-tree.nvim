local vim = vim
local fs = require('neo-tree.sources.filesystem')

local commands = {
  open = function(state)
    local tree = state.tree
    local node = tree:get_node()
    if node.type == 'directory' then
      if node.loaded == false then
        fs.loadChildren(node.id)
      elseif node:has_children() then
        local updated = false
        if node:is_expanded() then
          updated = node:collapse()
        else
          updated = node:expand()
        end
        if updated then
          tree:render()
        else
          tree:render()
        end
      end
    else
      vim.cmd("wincmd p")
      vim.cmd("e " .. node.id)
    end
  end,
  refresh = function(state)
    fs.refresh()
  end,
  set_root = function(state)
    local tree = state.tree
    local node = tree:get_node()
    if node.type == 'directory' then
      fs.navigate(node.id)
    end
  end,
  toggle_hidden = function(state)
    fs.toggle_hidden()
  end,
  toggle_gitignore = function (state)
    fs.toggle_gitignore()
  end,
  up = function(state)
    fs.navigateUp()
  end,
}

return commands
