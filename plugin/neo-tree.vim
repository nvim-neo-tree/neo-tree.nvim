if exists('g:loaded_neo_tree')
  finish
endif
let g:loaded_neo_tree = 1

command! NeoTreeClose  lua require("neo-tree").close()
command! NeoTreeFocus  lua require("neo-tree").focus()
command! NeoTreeShow   lua require("neo-tree").show(nil, true)
command! NeoTreeReveal lua require("neo-tree.sources.filesystem").reveal_current_file()
