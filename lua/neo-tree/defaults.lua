local config = {
    defaultSource = "filesystem",
    filesystem = {
        window = {
            position = "left",
            width = 40,
            mappings = {
                ["<cr>"] = "open",
                ["<bs>"] = "up",
                ["."] = "setRoot",
                ["H"] = "toggleHidden",
                ["I"] = "toggleGitIgnore"
            }
        },
        filters = {
            showHidden = false,
            respectGitIgnore = true
        },
        before_render = function(state)

        end,
        functions = {
            icon = function(config, node, state)
                local icon = config.icon
                local highlight = config.highlight
                if not icon then
                    if node.type == "directory" then
                        highlight = "NvimTreeFolderIcon"
                        if node.open then
                            icon = config.folder_open or "-"
                        else
                            icon = config.folder_closed or "+"
                        end
                    elseif node.type == "file" then
                        icon = config.file or " "
                        highlight = "NvimTreeFileIcon"
                    end
                end
                return {
                    text = icon .. " ",
                    highlight = highlight
                }
            end,
            name = function(config, node, state)
                return {
                    text = node.name,
                    highlight = config.highlight or "NvimTreeNormal"
                }
            end,
        },
        renderers = {
            directory = {
                { "icon" },
                { "name", highlight = "NvimTreeDirectory" }
            },
            file = {
                { "icon" },
                { "name" }
            }
        }
    }
}
return config
