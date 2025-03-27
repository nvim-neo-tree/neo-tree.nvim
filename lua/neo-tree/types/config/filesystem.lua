---@meta

---@alias neotree.Config.Cwd "tab"|"window"|"global"

---@class neotree.Config.Filesystem.CwdTarget
---@field sidebar neotree.Config.Cwd?
---@field current neotree.Config.Cwd?

---@class neotree.Config.Filesystem.FilteredItems
---@field visible boolean?
---@field force_visible_in_empty_folder boolean?
---@field show_hidden_count boolean?
---@field hide_dotfiles boolean?
---@field hide_gitignored boolean?
---@field hide_hidden boolean?
---@field hide_by_name string[]?
---@field hide_by_pattern string[]?
---@field always_show string[]?
---@field always_show_by_pattern string[]?
---@field never_show string[]?
---@field never_show_by_pattern string[]?

---@alias neotree.Config.Filesystem.FindArgsHandler fun(cmd:string, path:string, search_term:string, args:string[]):string[]

---@class neotree.Config.Filesystem.FollowCurrentFile
---@field enabled boolean?
---@field leave_dirs_open boolean?

---@alias neotree.Config.HijackNetrwBehavior
---|"open_default" # opening a directory opens neo-tree with the default window.position.
---|"open_current" # opening a directory opens neo-tree within the current window.
---|"disabled" # opening a directory opens neo-tree within the current window.

---@class neotree.Config.Filesystem.Renderers : neotree.Config.Renderers

---@class neotree.Config.Filesystem.Window : neotree.Config.Source.Window
---@field fuzzy_finder_mappings table<string, neotree.FuzzyFinder.Commands|"close">?

---@class (exact) neotree.Config.Filesystem : neotree.Config.Source
---@field async_directory_scan "auto"|"always"|"never"|nil
---@field scan_mode "shallow"|"deep"|nil
---@field bind_to_cwd boolean?
---@field cwd_target neotree.Config.Filesystem.CwdTarget?
---@field check_gitignore_in_search boolean?
---@field filtered_items neotree.Config.Filesystem.FilteredItems?
---@field find_by_full_path_words boolean?
---@field find_command string?
---@field find_args table<string, string[]>|neotree.Config.Filesystem.FindArgsHandler|nil
---@field group_empty_dirs boolean?
---@field search_limit integer?
---@field follow_current_file neotree.Config.Filesystem.FollowCurrentFile?
---@field hijack_netrw_behavior neotree.Config.HijackNetrwBehavior?
---@field use_libuv_file_watcher boolean?
---@field renderers neotree.Config.Filesystem.Renderers?
---@field window neotree.Config.Filesystem.Window?
