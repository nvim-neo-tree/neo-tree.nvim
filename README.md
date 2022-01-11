# Neo-tree.nvim

Neo-tree is a Neovim plugin to browse the file system and other tree like
structures in a sidebar or floating window.

An example of the tree structure for viewing the filesystem:

![Neo-tree file system](https://github.com/nvim-neo-tree/resources/raw/main/images/Neo-tree-filesystem.png)

## Overview

- [Quickstart](#quickstart)
- [Commands](#commands)
- [Builtin Sources](#builtin-sources)
  - [Filesystem](#filesystem)
  - [Buffers](#buffers)
  - [Git Status](#git_status)
- [Plugin Status](#plugin-status)
- [Configuration & Customization](#configuration-and-customization)
- [Why?](#why)
- [Contributions](#contributions)
- [Acknowledgements](#acknowledgements)

## Quickstart

Example for `packer`:

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

        -- For each source below, see 'docs/sources/{source}.md' for options
        filesystem = { ... },
        buffers = { ... },
        git_status = { ... },
      })
    end
}
```

## Commands

Interfacing with _NeoTree_ comes completely from one command - `NeoTree` which itself takes
a number of positional and keyword arguments to interact with different tree sources and
their associated behavior.

### General

**Source**
_type_: `positional`

See [Sources](#sources) for more information.

`:NeoTree <> ...`

| Values       | Description |
| ------------ | ----------- |
| `filesystem` | The `filesystem` source |
| `git_status` | The `git_status` source |
| `buffers`    | The `buffers` source |
| `current`    | The currently focused source, if any |

**Action**
_type_: `keyword`

`NeoTree ... action=<>`

| Values   | Description |
| -------- | ----------- |
| `reveal` | Focus the window and find the buffer the command was called from in the tree |
| `show`   | Show the window, keeping the previous state, without focusing |
| `focus`  | Show and focus, keeping the previous state |
| `close`  | Close the current source, or all sources if none was given |

**Toggle**
_type_: `keyword`

`NeoTree ... toggle=<>`

| Values   | Description |
| -------- | ----------- |
| `false`  | Do not perform the action as a toggle, default |
| `true`   | Perform the action as a toggle |

**Window**
_type_: `keyword`

`NeoTree ... window=<>`

| Values   | Description |
| -------- | ----------- |
| `split`  | Perform the action in a split window, default |
| `float`  | Perform the action in a floating window |

Complete documentation can be found in the help file `:h neo-tree` or online
at [neo-tree.txt](/doc/neo-tree.txt)

## Builtin Sources

Neo-tree is built on the idea of supporting various sources. Sources are
basically interface implementations whose job it is to provide a list of
hierachical items to be rendered, along with commands that are appropriate to
those items.

Links in each of the sections below have more information about the different sources.

### filesystem

The [filesystem](doc/sources/filesystem.md) source displays your files and folders. An example of this
tree in a floating window:

```
:NeoTree filesystem action=reveal window=float
```

### buffers

The [buffers](doc/sources/buffers.md) source displays your open buffers. This is
the same list you would see from `:ls`. An example of this tree in a split window:

```
:NeoTree buffers action=show window=split
```

### git_status

The [git_status](doc/sources/git_status.md) source displays the result of `git status` in a tree. It includes
commands for adding, unstaging, reverting, and committing. An example of interacting with it in a floating window:

```
:NeoTree git_status window=float
```

## Plugin Status

This is a fully functional file browser with navigation, mutation,
`git status`, and filtering. It can also display a list of open buffers. Other
sources that may be added include things like tags, Treesitter or LSP document
structures, etc.

## Configuration and Customization

The general idea of this plugin is to provide an simple and flexible tree structure
for displaying some pre-built sources, but also allowing users to specify their
own. The way that is acheived is by making everything a function, or a reference
to a built-in function. All of the built-in functions can be replaced with your
own implimentation, or you can add new ones.

Each node in the tree is created from the renderer specified for the given node
type, and each renderer is a list of component configs. Each component is a
function, either built-in or specified in your own the `setup()` config. Those
functions are called with the config, node, and state of the plugin, and return
the text and highlight group for the component.

Additionally, each source has a `before_render()` function that you can
override and use to gather any additonal information you want to use in your
components. This function is currently used to gather the `git status` and
diagnostics for the tree. If you want to skip that, override the function and
leave the parts you with to skip out. If you want to show some other data, gather it in
`before_render()`, create a component to display it, and reference that
component in the renderer for the `file` and/or `directory` type.

Details on how to configure everything is in the help file at `:h neo-tree` or
online at [neo-tree.txt](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/doc/neo-tree.txt)

## Why

There are many tree plugins for _(neo)vim, so why make another one? Well, I
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

Everything I know about writing a tree control in `lua`, I learned from:

- [nvim-tree.lua](https://github.com/kyazdani42/nvim-tree.lua)
