# Neo-tree.nvim

Neo-tree is a Neovim plugin to browse the file system and other tree like
structures in a sidebar **or** floating window. 

## Quickstart

Example for packer:
```lua
use {
  "nvim-neo-tree/neo-tree.nvim",
    branch = "v1.x",
    requires = { 
      "nvim-lua/plenary.nvim",
      "kyazdani42/nvim-web-devicons", -- not strictly required, but recommended
        "MunifTanjim/nui.nvim" 
    },
    config = function ()
      require("neo-tree").setup({
        popup_border_style = "rounded",
        filesystem = {
          window = {
            mappings = {
              ["<2-LeftMouse>"] = "open",
              ["<cr>"] = "open",
              ["S"] = "open_split",
              ["s"] = "open_vsplit",
              ["C"] = "close_node",
              ["<bs>"] = "navigate_up",
              ["."] = "set_root",
              ["H"] = "toggle_hidden",
              ["I"] = "toggle_gitignore",
              ["R"] = "refresh",
              ["/"] = "filter_as_you_type",
              ["f"] = "filter_on_submit",
              ["<c-x>"] = "clear_filter",
              ["a"] = "add",
              ["d"] = "delete",
              ["r"] = "rename",
              ["c"] = "copy_to_clipboard",
              ["x"] = "cut_to_clipboard",
              ["p"] = "paste_from_clipboard",
            }
          }
        },
        git_status = {
          window = {
            mappings = {
              ["<2-LeftMouse>"] = "open",
              ["<cr>"] = "open",
              ["S"] = "open_split",
              ["s"] = "open_vsplit",
              ["C"] = "close_node",
              ["R"] = "refresh",
              ["d"] = "delete",
              ["r"] = "rename",
              ["c"] = "copy_to_clipboard",
              ["x"] = "cut_to_clipboard",
              ["p"] = "paste_from_clipboard",
              ["A"]  = "git_add_all",
              ["gu"] = "git_unstage_file",
              ["ga"] = "git_add_file",
              ["gr"] = "git_revert_file",
              ["gc"] = "git_commit"
            }
          }
        }
      })
      vim.cmd([[nnoremap \ :NeoTreeReveal<cr>]])
    end
}
```

Here are the various ways to open the tree:

`:NeoTreeReveal` will find the current file in the tree and focus it. If the current file
is not within the current working directory, you will be prompted to change the
cwd.

` :NeoTreeFocus ` will open the window and switch to it. If Neo-tree is already open, it
will just switch focus to that window.

` :NeoTreeShow ` will show the window WITHOUT focusing it, leaving the focus on the current
file.

` :NeoTreeFloat ` will open the tree in a floating window instead of a sidebar.

There are also Toggle variants of the above commands, which will close the
window if it is already open: `NeoTreeRevealToggle` `NeoTreeShowToggle`
`NeoTreeFocusToggle` `NeoTreeFloatToggle`

You can also close the tree with: `:NeoTreeClose `

Complete documentation can be find in the vim help file `:h neo-tree` or online
at [neo-tree.txt](/doc/neo-tree.txt)

An example configuration for the filesystem source with proper syntax
highlighting can also be viewed at the [filesystem README](/lua/neo-tree/sources/filesystem/README.md)

## Sources

Neo-tree is built on the idea of supporting various sources. Sources are
basically interface implimentations whose job it is to provide a list of
hierachical items to be rendered, along with commands that are appropriate to
those items.

### filesystem
The default source is `filesystem`, which displays your files and folders. This
is the default source in commands when none is specified.

### buffers
Another available source is `buffers`, which displays your open buffers. This is
the same list you would see from `:ls`. To show with the `buffers` list, use:
```
:NeoTreeShow buffers
```
or `:NeoTreeFocus buffers` or `:NeoTreeShow buffers` or `:NeoTreeFloat buffers`

### git_status
This view take the results of the `git status` command and display them in a
tree. It includes commands for adding, unstaging, reverting, and committing.


## Status

This is a fully functional file browser with navigation, mutation,
git status, and filtering. It can also display a list of open buffers. Other
sources that may be added include things like tags, treesitter or lsp document
structures, git status, etc.

## Configuration and Customization

This is designed to be flexible. The way that is acheived is by making
everything a function, or a reference to a built-in function. All of the
built-in functions can be replaced with your own implimentation, or you can 
add new ones.

Each node in the tree is created from the renderer specified for the given node
type, and each renderer is a list of component configs. Each component is a
function, either built-in or specified in your own the setup() config. Those 
functions are called with the config, node, and state of the plugin, and return
the text and highlight group for the component.

Additionally, each source has a `before_render()` function that you can
override and use to gather any additonal information you want to use in your
components. This function is currently used to gather the git status and
diagnostics for the tree. If you want to skip that, override the function and
leave that part out. If you want to show some other data, gather it in
`before_render()`, create a component to display it, and reference that
component in the renderer for the `file` and/or `directory` type.

Details on how to configure everything is in the help file at `:h neo-tree` or
online at [neo-tree.txt](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/doc/neo-tree.txt)


## Why?

There are many tree plugins for (neo)vim, so why make another one? Well, I
wanted something that was:

1. Easy to maintain and enhance.
2. Stable.
3. Easy to customize.

### Easy to maintain and enhance

This plugin is designed to grow and be flexible. This is accomplished by making
the code as decoupled and functional as possible. It shouldn't be necessary to
touch any of the core plumbing to add new functionality. Aside from bug fixes,
the code outside of the `sources` directory should not be touched to add new
features. Hopefully new contributors will find it easy to work with.

One big difference between this plugin and the ones that came before it, which
is also what finally pushed me over the edge into making a new plugin, is that
we now have libraries to build upon that did not exist when other tree plugins
were created. Most notably, [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
and [plenary.nvm](https://github.com/nvim-lua/plenary.nvim). Building upon
shared libraries will go a long way in making neo-tree easy to maintain.

### Stable

This project will have releases and release tags that follow a simplified
Semantic Versioning scheme. The quickstart instructions will always refer to
the latest stable major version. Following the **main** branch is for
contributors and those that always want bleeding edge. There will be branches
for **v1.x**, **v2.x**, etc which will receive updates after a short testing
period in **main**. You should be safe to follow those branches and be sure
your tree won't break in an update. There will also be tags for each release
pushed to those branches named **v1.1**, **v1.2**, etc. If stability is
critical to you, or a bug accidentally make it into **v1.x**, you can use those
tags instead. It's possible we may backport bug fixes to those tags, but no
garauntees on that.

There will never be a breaking change within a major version (1.x, 2.x, etc.) If
a breaking change is needed, there will be depracation warnings in the prior
major version, and the breaking change will happen in the next major version.

### Easy to Customize

This will follow in the spirit of plugins like
[lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) and
[nvim-cokeline](https://github.com/noib3/nvim-cokeline). Everything will be
configurable and take either strings, tables, or functions. You can take sane
defaults or build your tree items from scratch. There should be the ability to
add any features you can think of through existing hooks in the setup function.

## Contributions

Contributions are encouraged. Please see [CONTRIBUTING](CONTRIBUTING.md) for more details.

## Acknowledgements

This project relies upon these two excellent libraries:
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for all UI components, including the tree!
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for backend utilities, such as scanning the filesystem.

The design is heavily inspired by these excellent plugins:
- [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)
- [nvim-cokeline](https://github.com/noib3/nvim-cokeline)

Everything I know about writing a tree control in lua, I learned from:
- [nvim-tree.lua](https://github.com/kyazdani42/nvim-tree.lua)
