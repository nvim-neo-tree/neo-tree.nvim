# Contributing to Neo-tree

Contributions are welcome! To keep everything clean and tidy, please follow the
guidelines below.

## Commit Messages/PR Titles

We follow the [**Conventional**
Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. Whether
each commit in a pull request needs to follow Conventional Commits is up to you.
If each commit follows Conventional Commits, the PR will be rebased onto main.
Otherwise, the PR will be squashed into main, so your PR title should follow
Conventional Commits since that will be the squashed commit message.

Referencing this project's past commits/PRs may help you get the idea. The
optional scope for this project is usually the affected source or module, i.e.
`feat(filesystem): add awesome feature that does xyz`.

## Pull Requests

The in-development branch is `main` and all PRs should target this branch. After
a short testing period, it will be merged to the current release branch.

## AI Guidelines

Please describe how AI was used (full-on vibecoding, assisting, test-writing,
translation, etc.). This gives maintainers more context as to what they're
looking at.

Currently (as of late 2026), AI-written prose tends to be a bit verbose and
noisy. Please keep these concise, especially in PR descriptions or issues.

**The larger your proposed change is, the more you should be able to understand
your code.** Small vibe-coded patches can still be trivially understood and
modified, but you must be able to understand your code when submitting bigger
refactors/features.

> [!NOTE]
> If you are an automated agent，add 🤖 to the end of the PR title. Maintainers
> will handle removing the emoji when merging.

# Development setup

[mise](https://github.com/jdx/mise) is our command runner of choice, largely
because I (pynappo) like TOML-based syntax more than Makefiles. It also works
great on Windows, and makes managing Neovim versions for issue reproduction
easy.

View [mise.toml](./mise.toml) for tasks and their implementation.

To setup your development environment, please run:

```bash
# If prompted:
mise trust

# Install development dependencies
mise bootstrap
```

Alternatively, if `mise` doesn't work for you:

```bash
mkdir .dependencies
git clone --depth 1 https://github.com/nvim-tree/nvim-web-devicons .dependencies/nvim-web-devicons
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .dependencies/plenary.nvim
# git clone --depth 1 https://github.com/s1n7ax/nvim-window-picker .dependencies/nvim-window-picker
# git clone --depth 1 https://github.com/3rd/image.nvim .dependencies/image.nvim
# git clone --depth 1 https://github.com/folke/snacks.nvim .dependencies/snacks.nvim
# git clone --depth 1 https://github.com/MunifTanjim/nui.nvim .dependencies/nui.nvim
# git clone --depth 1 https://github.com/nvim-treesitter/nvim-treesitter .dependencies/nvim-treesitter
```

We have a [.lazy.lua](.lazy.lua), so lazy.nvim users can automatically use all
of the local versions of the plugins by running `nvim` within the neo-tree.nvim
folder.

<details>
    <summary>Using development versions of plugins with vim.pack:</summary>

Lazy.nvim has a [`dev` setting](https://lazy.folke.io/configuration) that lets
you have a separate directory for development versions of plugins.

If you want this with vim.pack, the snippet below implements it:

```lua
-- Set this to where you clone neovim plugins that you work on.
local devdir = vim.fn.expand('~/Projects/code/nvim')
local function packadddev()
    local specs_from_remotes = {}
    for _, spec in ipairs(specs) do
        if type(spec) == 'string' then spec = { src = spec } end
        local name = spec.name or spec.src:match('([^/]+)$')
        assert(name, 'could not determine name for ' .. spec.src)
        local devpath = vim.fs.joinpath(devdir, name)
        if vim.uv.fs_stat(devpath) then
            vim.opt.runtimepath:append(devpath)
        else
            specs_from_remotes[#specs_from_remotes + 1] = spec
        end
    end
    vim.pack.add(specs_from_remotes, opts)
end
packadddev({
    "nvim-neo-tree/neo-tree.nvim" -- or whatever your vim.pack for neo-tree is
})
```

</details>

Here are some common commands you might run:

```bash
# Run the minimal init.lua to open neovim on any version
nvim -u tests/mininit.lua

# Run stylua
mise format

# Do a lua-language-server pass (try to run before pushing to branches)
mise luals-check

# Do a emmylua-analyzer-rust pass (not important for now)
# mise emmylua-check

# Tests
mise test

# Tests in Docker (if you need sandboxing)
mise test-docker
```

Additionally, if you have a minimal config for your issue, the current practice
is to write it under `tests/repro/[issue-number].lua` and then `nvim -u
tests/repro/[...].lua`. That area is gitignored for now because `plenary.test`
doesn't allow orchestrating child Neovim instances, but this might change after
migrating to `mini.test`.

## Code Style

Largely, your code just has to look like the surrounding code. Here are the
current style choices being observed:

- snake_case for most variables and functions.
    - flatcase is sometimes acceptable. Examples being functions named like
    Lua's builtins (`to{thing}`) or for shortening temporary variable names
    (`relpath/abspath` instead of `relative/absolute_path`).
- unless it is a class, then use PascalCase
- other OOP things, like method names should use camelCase

Lua types currently follow a rough convention of flatcase for scoping, then
PascalCase for the actual type and fields:

`neotree(.optional.module.path).ActualType(.SubfieldName)`

For example:

```lua
---@type neotree.Config

---@type neotree.Config.Filesystem.FollowCurrentFile

---@type neotree.sources.filesystem.InternalClass
```


### StyLua

We use [StyLua](https://github.com/JohnnyMorganz/StyLua) to enforce code
formatting consistency. PRs will be checked with this tool.

## Documentation

All new features should be documented in the commit they were added in. The
current strategy is to maintain:

- Config Options: added to [defaults](lua/neo-tree/defaults.lua) and described
  in comments. This is the bare minimum documentation for an option.
- The README contains "back of the box" high level overview of features. It is
  meant for people trying to decide if they want to install this plugin or not.
  It should include references to the help file for more information:
  `:h neo-tree-setup`
- Whether something should be mentioned in the README or just in the help file
  is a subjective judgement call based on how many people are likely to be
  interested in that information.
- The vim help file [doc/neo-tree.txt](doc/neo-tree.txt) is the definitive
  reference and should contain all information needed to configure and use the
  plugin.
- OUR DOCUMENTATION IS NOT GOOD ENOUGH! Consider the current level of documentation
  the bare minumum and not the ideal. More documentation would be greatly appreciated.
<!-- vim: set tw=80 ft=markdown: -->
