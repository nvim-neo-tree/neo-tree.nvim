local M = {}
local parser_pattern = "parser/%s.*"
local root_dir = vim.fs.find("neo-tree.nvim", { upward = true, limit = 1 })[1]
assert(root_dir, "no neo-tree found")

---https://github.com/HiPhish/rainbow-delimiters.nvim/blob/master/test/xdg/config/nvim/plugin/ts-ensure.lua#L3
---Install a treesitter parser synchronously.
---@param lang string
---@param timeout number?
function M.ensure_parser(lang, timeout)
  assert(vim.fn.has("nvim-0.11") == 1, "ensure_parser only works on nvim 0.11+")
  timeout = timeout or 2 * 60 * 1000
  -- install w/ nvim-treesitter master command

  local nts = require("nvim-treesitter")
  nts.setup({
    install_dir = root_dir .. "/.repro",
  })
  local result = nts.install(lang):wait(timeout)
  if not result then
    local msg = string.format("Error installing Tree-sitter parsers: %s", vim.inspect(lang))
    error(msg)
  end
  -- assert(#vim.api.nvim_get_runtime_file(parser_pattern:format(lang), true) > 0)
end

return M
