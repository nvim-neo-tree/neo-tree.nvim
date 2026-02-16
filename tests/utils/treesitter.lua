local M = {}
local parser_pattern = "parser/%s.*"

---https://github.com/HiPhish/rainbow-delimiters.nvim/blob/master/test/xdg/config/nvim/plugin/ts-ensure.lua#L3
---Install a treesitter parser synchronously.
---@param lang string
---@param timeout number?
function M.ensure_parser(lang, timeout)
  assert(vim.fn.has("nvim-0.11") == 1, "ensure_parser only works on nvim 0.11+")
  timeout = timeout or 2 * 60 * 1000
  -- install w/ nvim-treesitter master command
  local nts = require("nvim-treesitter")
  local result = nts.install(lang):wait(timeout)
  if not result then
    local msg = string.format("Error installing Tree-sitter parsers: %s", vim.inspect(lang))
    error(msg)
  end
end

return M
