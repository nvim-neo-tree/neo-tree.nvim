--- A backport from v0.10

--- @class neotree._vim.api.keyset.create_autocmd.callback_args
--- @field id integer autocommand id
--- @field event string name of the triggered event |autocmd-events|
--- @field group? integer autocommand group id, if any
--- @field match string expanded value of <amatch>
--- @field buf integer expanded value of <abuf>
--- @field file string expanded value of <afile>
--- @field data? any arbitrary data passed from |nvim_exec_autocmds()|                       *event-data*
