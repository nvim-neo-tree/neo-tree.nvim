# Filesystem

This source is used to:
- Browse the filesystem
- Control the current working directory of nvim
- Add/Copy/Delete/Move/Rename files and directories
- Search the Filesystem
- Monitor git status for the current working directory

See below for an example configuration of this source:

```lua
local highlights = require('neo-tree.ui.highlights')

require("neo-tree").setup({
  -- The default_source is the one used when calling require('neo-tree').show()
  -- without a source argument.
  default_source = "filesystem",
  popup_border_style = "NC", -- "double", "none", "rounded", "shadow", "single" or "solid"
  -- "NC" is a special style that works well with NormalNC set
  filesystem = {
    follow_current_file = false, -- This will find and focus the file in the
    -- active buffer every time the current file is changed, if the tree is open.
    use_libuv_file_watcher = false, -- This will use the OS level file watchers 
    -- to detect changes instead of relying on nvim autocmd events.
    window = {
      position = "left",
      width = 40,
      -- Mappings for tree window. See |Neo-tree-Mappings| for built-in 
      -- commands. You can also create your own commands by providing a 
      -- function instead of a string. See the built-in commands for examples.
      mappings = {
        ["<2-LeftMouse>"] = "open",
        ["<cr>"] = "open",
        ["S"] = "open_split",
        ["s"] = "open_vsplit",
        ["<bs>"] = "navigate_up",
        ["."] = "set_root",
        ["H"] = "toggle_hidden",
        ["I"] = "toggle_gitignore",
        ["R"] = "refresh",
        ["/"] = "filter_as_you_type",
        --["/"] = "none" -- Assigning a key to "none" will remove the default mapping
        ["f"] = "filter_on_submit",
        ["<C-x>"] = "clear_filter",
        ["a"] = "add",
        ["d"] = "delete",
        ["r"] = "rename",
        ["c"] = "copy_to_clipboard",
        ["x"] = "cut_to_clipboard",
        ["p"] = "paste_from_clipboard",
      }
    },
    search_limit = 50, -- max number of search results when using filters
    filters = {
      show_hidden = false,
      respect_gitignore = true,
    },
    bind_to_cwd = true, -- true creates a 2-way binding between vim's cwd and neo-tree's root
    before_render = function(state)
      -- This function is called after the file system has been scanned,
      -- but before the tree is rendered. You can use this to gather extra
      -- data that can be used in the renderers.
      local git = require("neo-tree.git")
      state.git_status_lookup = git.status()
    end,
    -- The components section provides custom functions that may be called by 
    -- the renderers below. Each componment is a function that takes the
    -- following arguments:
    --      config: A table containing the configuration provided by the user
    --              when declaring this component in their renderer config.
    --      node:   A NuiNode object for the currently focused node.
    --      state:  The current state of the source providing the items.
    --
    -- The function should return either a table, or a list of tables, each of which
    -- contains the following keys:
    --    text:      The text to display for this item.
    --    highlight: The highlight group to apply to this text.
    components = {
      hello_node = function (config, node, state)
        local text = "Hello " .. node.name
        if state.search_term then
          text = string.format("Hello '%s' in %s", state.search_term, node.name)
        end
        return {
          text = text,
          highlight = config.highlight or highlights.FILE_NAME,
        }
      end
    },
    -- This section provides the renderers that will be used to render the tree.
    -- The first level is the node type.
    -- For each node type, you can specify a list of components to render.
    -- Components are rendered in the order they are specified.
    -- The first field in each component is the name of the function to call.
    -- The rest of the fields are passed to the function as the "config" argument.
    renderers = {
      directory = {
        {
            "indent",
            with_markers = true,
            indent_marker = "│",
            last_indent_marker = "└"
        },
        {
          "icon",
          folder_closed = "",
          folder_open = "",
          padding = " ",
        },
        { "current_filter" },
        { "name" },
        --{
        --  "symlink_target",
        --  highlight = "NeoTreeSymbolicLinkTarget",
        --},
        {
          "clipboard",
          highlight = "NeoTreeDimText"
        },
        --{ "git_status" },
      },
      file = {
        {
            "indent",
            with_markers = true,
            indent_marker = "│",
            last_indent_marker = "└"
        },
        {
          "icon",
          default = "*",
          padding = " ",
        },
        --{ "hello_node", highlight = "Normal" }, -- For example, don't actually
        -- use this!
        { "name" },
        --{
        --  "symlink_target",
        --  highlight = "NeoTreeSymbolicLinkTarget",
        --},
        {
          "clipboard",
          highlight = "NeoTreeDimText"
        },
        {
          "git_status",
          highlight = "NeoTreeDimText"
        }
      },
    }
  }
})
```
