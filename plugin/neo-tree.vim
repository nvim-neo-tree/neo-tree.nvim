if exists('g:loaded_neo_tree')
  finish
endif
let g:loaded_neo_tree = 1

command! -nargs=? NeoTreeClose  lua require("neo-tree").close_all("<args>")
command! -nargs=? NeoTreeFocus  lua require("neo-tree").focus("<args>")
command! -nargs=? NeoTreeShow   lua require("neo-tree").show("<args>", true)
command! NeoTreeReveal lua require("neo-tree.sources.filesystem").reveal_current_file()
