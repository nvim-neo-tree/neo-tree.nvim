if exists('g:loaded_neo_tree')
  finish
endif
let g:loaded_neo_tree = 1

command! -nargs=? NeoTreeClose  lua require("neo-tree").close_all("<args>")
command! -nargs=? NeoTreeFloat  lua require("neo-tree").float("<args>")
command! -nargs=? NeoTreeFocus  lua require("neo-tree").focus("<args>")
command! -nargs=? NeoTreeShow   lua require("neo-tree").show("<args>", true)
command! NeoTreeReveal lua require("neo-tree").reveal_current_file("filesystem", false) 

command! -nargs=? NeoTreeFloatToggle  lua require("neo-tree").float("<args>", true)
command! -nargs=? NeoTreeFocusToggle  lua require("neo-tree").focus("<args>", true, true)
command! -nargs=? NeoTreeShowToggle   lua require("neo-tree").show("<args>", true, true, true)
command! NeoTreeRevealToggle lua require("neo-tree").reveal_current_file("filesystem", true)

command! -nargs=? NeoTreeSetLogLevel   lua require("neo-tree").set_log_level("<args>")
command! NeoTreeLogs lua require("neo-tree").show_logs()
