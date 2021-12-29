local config = {
    -- The default_source is the one used when calling require('neo-tree').show()
    -- without a source argument.
    default_source = "filesystem",
    popup_border_style = "rounded",
    filesystem = {
        window = {
            position = "left",
            width = 40,
            -- Mappings for tree window. See https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/sources/filesystem/commands.lua
            -- for built-in commands. You can also create your own commands by
            -- providing a function instead of a string. See the built-in
            -- commands for examples.
            mappings = {
                ["<cr>"] = "open",
                ["<LeftMouse>"] = "open",
                ["S"] = "open_split",
                ["s"] = "open_vsplit",
                ["<bs>"] = "navigate_up",
                ["."] = "set_root",
                ["H"] = "toggle_hidden",
                ["I"] = "toggle_gitignore",
                ["R"] = "refresh",
                ["/"] = "filter",
                ["a"] = "add",
                ["c"] = "copy_to_clipboard",
                ["d"] = "delete",
                ["p"] = "paste_from_clipboard",
                ["r"] = "rename",
                ["x"] = "cut_to_clipboard",
                ["???"] = "show_debug_info"
            }
        },
        filters = {
            show_hidden = false,
            respect_gitignore = true
        },
        bind_to_cwd = true, -- true creates a 2-way binding between vim's cwd and neo-tree's root
        search_depth = 4, -- How deep to search for files, nil for infinite
        before_render = function(state)
            -- This function is called after the file system has been scanned,
            -- but before the tree is rendered. You can use this to gather extra
            -- data that can be used in the renderers.
            local utils = require("neo-tree.utils")
            state.git_status_lookup = utils.get_git_status()
        end,
        -- This section provides the functions that may be called by the renderers below.
        functions = {
            icon = function(config, node, state)
                local icon = config.default or " "
                local highlight = config.highlight
                if node.type == "directory" then
                    highlight = "NvimTreeFolderIcon"
                    if node:is_expanded() then
                        icon = config.folder_open or "-"
                    else
                        icon = config.folder_closed or "+"
                    end
                elseif node.type == "file" then
                    local success, web_devicons = pcall(require, 'nvim-web-devicons')
                    if success then
                        devicon, hl = web_devicons.get_icon(node.name, node.ext)
                        icon = devicon or icon
                        highlight = hl or highlight
                    else
                        highlight = "NvimTreeFileIcon"
                    end
                end
                return {
                    text = icon .. config.padding,
                    highlight = highlight
                }
            end,
            name = function(config, node, state)
                local highlight = config.highlight or "NeoTreeFileName"
                if node.type == "directory" then
                    highlight = "NeoTreeDirectoryName"
                end
                if node:get_depth() == 1 then
                    highlight = "NeoTreeRootName"
                else
                    local git_status = state.functions.git_status(config, node, state)
                    if git_status and git_status.highlight then
                        highlight = git_status.highlight
                    end
                end
                return {
                    text = node.name,
                    highlight = highlight
                }
            end,
            clipboard = function(config, node, state)
                local clipboard = state.clipboard or {}
                local clipboard_state = clipboard[node:get_id()]
                if not clipboard_state then
                    return {}
                end
                return {
                    text = " (".. clipboard_state.action .. ")",
                    highlight = config.highlight or "Comment"
                }
            end,
            git_status = function(config, node, state)
                local git_status_lookup = state.git_status_lookup
                if not git_status_lookup then
                    return {}
                end
                local git_status = git_status_lookup[node.path]
                if not git_status then
                    return {}
                end

                local highlight = "Comment"
                if git_status:match("M") then
                    highlight = "NeoTreeGitModified"
                elseif git_status:match("[ACR]") then
                    highlight = "NeoTreeGitAdded"
                end

                return {
                    text = " [" .. git_status .. "]",
                    highlight = highlight
                }
            end,
            filter = function(config, node, state)
                local filter = node.search_pattern or ""
                if filter == "" then
                    return {}
                end
                return {
                    text = string.format('Filter "%s" in ', filter),
                    highlight = config.highlight or "Comment"
                }
            end,
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
                    "icon",
                    folder_closed = "",
                    folder_open = "",
                    padding = " ",
                },
                { "filter" },
                {
                    "name",
                    highlight = "NeoTreeDirectoryName"
                },
                {
                    "clipboard",
                    highlight = "Comment"
                },
                --{ "git_status" },
            },
            file = {
                {
                    "icon",
                    default = "*",
                    padding = " ",
                },
                { "name" },
                {
                    "clipboard",
                    highlight = "Comment"
                },
                --{ "git_status" },
            },
        }
    }
}
return config
