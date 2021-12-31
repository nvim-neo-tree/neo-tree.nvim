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

For a configuration example and default mappings, see [defaults.lua](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/defaults.lua).
Anything passed to the setup() function will be merged with those default values.
Proper documentation is coming soon.

## Status

This is currently functional as a basic file browser but definitely not
complete. The biggest issue is that there is no documentation at all! I plan on
adding that when I get close to the first release.

The first version of this plugin will provide a source for the file system and
establish the interface for other sources. Other sources that may include things
like tags, treesitter or lsp document structures, git status, open buffers 
list, etc.

## Why?

There are many tree plugins for (neo)vim, so why make another one? Well, I
wanted something that was:

1. Easy to maintain and enhance.
2. Stable.
3. Easy to customize.

### Easy to maintain and enhance

This plugin is designed from the start to eventually have all the features that 
any one can want from a mature tree plugin. This is not a "lite" or "simple"
plugin, although that does not mean it's not fast and efficient. It should mean
that it will be easier to continually add new features, and hopefully new
contributors will find it easy to work with.

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
