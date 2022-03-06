local utils = require "neo-tree.utils"

local migrate = function (config)
  local messages = {}

  local moved = function (old, new, converter)
    local exising = utils.get_value(config, old)
    if type(exising) ~= "nil" then
      if type(converter) == "function" then
        exising = converter(exising)
      end
      utils.set_value(config, new, exising)
      config[old] = nil
      messages[#messages + 1] = string.format("The `%s` option has been deprecated, please use `%s` instead.", old, new)
    end
  end

  local opposite = function (value)
    return not value
  end

  moved("filesystem.filters", "filesystem.filtered_items")
  moved("filesystem.filters.show_hidden", "filesystem.filtered_items.hide_dotfiles", opposite)
  moved("filesystem.filters.respect_gitignore", "filesystem.filtered_items.hide_gitignored")
  moved("filesystem.filters.gitignore_source", "filesystem.filtered_items.gitignore_source")

  return messages
end

return {
  migrate = migrate
}
