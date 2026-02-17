local M = {}
local root_markers1 = {
  ".emmyrc.json",
  ".luarc.json",
  ".luarc.jsonc",
}
local root_markers2 = {
  ".luacheckrc",
  ".stylua.toml",
  "stylua.toml",
  "selene.toml",
  "selene.yml",
}

---@type vim.lsp.Config
local config = {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = vim.fn.has("nvim-0.11.3") == 1 and { root_markers1, root_markers2, { ".git" } }
    or vim.list_extend(vim.list_extend(root_markers1, root_markers2), { ".git" }),
  settings = {
    Lua = {
      codeLens = { enable = true },
      hint = { enable = true, semicolon = "Disable" },
    },
  },
}

M.enable_lua_ls = function()
  vim.lsp.config("lua_ls", config)
  vim.lsp.enable("lua_ls")
end
return M
