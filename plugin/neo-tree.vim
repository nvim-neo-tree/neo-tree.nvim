if exists('g:loaded_neo_tree')
  finish
endif

let g:loaded_neo_tree = 1

command! -nargs=* NeoTree lua require("neo-tree.utils.command").run(unpack({<f-args>}))

" [x] command! -nargs=? NeoTreeClose  lua require("neo-tree").close_all("<args>")
" [x] command! -nargs=? NeoTreeFloat  lua require("neo-tree").float("<args>")
" [x] command! -nargs=? NeoTreeFocus  lua require("neo-tree").focus("<args>")
" [x] command! -nargs=? NeoTreeShow   lua require("neo-tree").show("<args>", true)
" [x] command! NeoTreeReveal lua require("neo-tree.sources.filesystem").reveal_current_file()

" [x] command! -nargs=? NeoTreeFloatToggle  lua require("neo-tree").float("<args>", true)
" [x] command! -nargs=? NeoTreeFocusToggle  lua require("neo-tree").focus("<args>", true, true)
" [x] command! -nargs=? NeoTreeShowToggle   lua require("neo-tree").show("<args>", true, true, true)
" [x] command! NeoTreeRevealToggle lua require("neo-tree.sources.filesystem").reveal_current_file(true)

" [ ] handle "current" as a source?
" [ ] did "show" used to not do anything unless called with "toggle" before?
