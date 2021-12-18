local config = {
    defaultSource = "fileSource",
    fileSource = {
        window = {
            position = "left",
            width = 40,
            mappings = {
                ["?"] = function(state)
                    print(vim.inspect(state))
                end,
                ["<space>"] = function(state)
                    local tree = state.tree
                    local node = tree:get_node()
                    local updated = false
                    if node:is_expanded() then
                        updated = node:collapse()
                    else
                        updated = node:expand()
                    end
                    if updated then
                        tree:render()
                    else
                        tree:render()
                    end
                end,
                ["j"] = function(state)
                    local tree = state.tree
                    local node = tree:get_node()
                    local updated = false
                    updated = node:expand()
                    if updated then
                        tree:render()
                    else
                        tree:render()
                    end
                end,
                ["k"] = function(state)
                    local tree = state.tree
                    local node = tree:get_node()
                    local updated = false
                    updated = node:collapse()
                    if updated then
                        tree:render()
                    else
                        tree:render()
                    end
                end,
                ["<cr>"] = function(state)
                    local tree = state.tree
                    local node = tree:get_node()
                    if node:has_children() then
                        local updated = false
                        if node:is_expanded() then
                            updated = node:collapse()
                        else
                            updated = node:expand()
                        end
                        if updated then
                            tree:render()
                        else
                            tree:render()
                        end
                    else
                        vim.cmd("wincmd p")
                        vim.cmd("e " .. node.id)
                    end
                end,
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
