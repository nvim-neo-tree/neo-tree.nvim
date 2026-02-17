local M = {}
local parser_pattern = "parser/%s.*"
local root_dir = vim.fs.find("neo-tree.nvim", { upward = true, limit = 1 })[1]
local install_dir = root_dir .. "/.repro", assert(root_dir, "no neo-tree found")

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
    install_dir = install_dir,
  })
  local parser_dir = require("nvim-treesitter.config").get_install_dir("parser")
  local result = nts.install(lang):wait(timeout)
  if not result then
    local msg = string.format("Error installing Tree-sitter parsers: %s", vim.inspect(lang))
    error(msg)
  end
  local files = {}

  -- vim.fs.dir returns an iterator that yields (name, type)
  for name, type in vim.fs.dir(parser_dir, { depth = math.huge }) do
    if type == "file" then
      -- Construct the full path
      table.insert(files, parser_dir .. "/" .. name)
    end
  end
  vim.print({
    parsers = files,
    rtp = vim.o.runtimepath,
  })

  assert(
    #vim.api.nvim_get_runtime_file(parser_pattern:format(lang), true) > 0,
    "Parser should have been installed"
  )
end

return M
