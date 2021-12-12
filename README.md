# neo-tree.nvim
Neovim plugin to manage and browse the file system and other tree like structures in a sidebar.

# Why?
There are many tree plugins for (neo)vim, so why make another one? Well, I wanted something that was:

1. Easy to maintain and enhance.
2. Stable.
3. Easy to customize.

# Easy to maintain
What makes the difference here is that this plugin will be designed from the begining to
be asynchronous and have all of the features you would want of a mature tree plugin. This
will avoid having to make comprimises to add in features later. Modules will be as small,
decoupled, and generic as possible. We will prefer functional over OOP. Code will be written
to be easily read by other humans.

The other big difference, and the one that finally pushed me over the edge into making a 
new plugin, is that we now have libraries to build upon that did not exist when other tree
plugins were created. Most notably, [nui.nvim](https://github.com/MunifTanjim/nui.nvim) and
[plenary.nvm](https://github.com/nvim-lua/plenary.nvim). Building upon shared libraries will
go a long way in improving that quality of neo-tree.

# Stable
This project will have releases and release tags that follow Semantic Versioning. The documentation
will always refer to the latest stable release. Following the 'main' branch is for contributors
and this that always want bleeding edge. There will be 1.x, 1.1.x, and 1.1.1 releases, so each user
can choose what level of updates they wish to receive.

There will never be a breaking change within a major version (1.x, 2.x, etc.) If there is,
there will be depracation warnings in the prior major version, and the breaking change will
happen in the naext major version.

# Easy to Customize
This will follow in the spirit of plugins like [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)
and [nvim-cokeline](https://github.com/noib3/nvim-cokeline). Everything will be configurable and take
either strings, tables, or functions. You can take sane defaults or build your tree items from scratch.
