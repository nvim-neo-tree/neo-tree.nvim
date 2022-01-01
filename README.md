# Neo-tree.nvim

Neo-tree is a Neovim plugin to browse the file system and other tree like
structures in a sidebar. 

## Quickstart

Example for packer:
```lua
    use {
        "nvim-neo-tree/neo-tree.nvim",
        branch = "main",
        requires = { "MunifTanjim/nui.nvim" },
        config = function ()
            require("neo-tree").setup()
            vim.cmd([[nnoremap \ :lua require("neo-tree").show()<cr>]])
        end
    }
```

Complete documentation can be find in the vim help file `:h neo-tree` or online
at [neo-tree.txt](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/doc/neo-tree.txt)

## Status

This is currently functional as a basic file browser with navigation, mutation,
git status, and filtering.

The file system source can serve as an example of how to create other sources.
Other sources that may include things like tags, treesitter or lsp document
structures, git status, open buffers list, etc.

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

Additionally, each source has a `before_render()` function that you can override 
and use to gather any additonal information you want to use in your components.
This function is currently used to gather the git status for the tree. If you 
want to skip that, override the function and leave that part out. If you want
to show LSP diagnostics, gather them in `before_render()`, create a component
to display them, and reference that component in the renderer for the `file`
and/or `directory` type.

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

This project will have releases and release tags that follow Semantic
Versioning. The quickstart instructions will always refer to the latest stable
major version. Following the 'main' branch is for contributors and those that
always want bleeding edge. There will be 1.x, 1.1.x, and 1.1.1 releases, so each
user can choose what level of updates they wish to receive.

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
