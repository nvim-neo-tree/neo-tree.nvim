if exists('g:loaded_neo_tree')
  finish
endif

command! -nargs=* -complete=custom,v:lua.require'neo-tree.command'.complete_args
            \ Neotree lua require("neo-tree.command")._command(<f-args>)

let g:loaded_neo_tree = 1
