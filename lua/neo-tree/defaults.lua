local config = {
    default_source = "filesystem",
    filesystem = {
        window = {
            position = "left",
            width = 40,
            mappings = {
                ["<cr>"] = "open",
                ["<2-LeftMouse>"] = "open",
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
        bind_to_cwd = true,
        before_render = function(state)

        end,
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
                return {
                    text = node.name,
                    highlight = config.highlight or "NvimTreeNormal"
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
                    highlight = "NvimTreeDirectory"
                },
                {
                    "clipboard",
                    highlight = "Comment"
                }
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
                }
            },
        }
    }
}
return config
