---@alias NeotreePathString string # Special type for string which represents a file path

---@class NeotreeState
---@field TODO nil # Figure out the fields

---@class NeotreeNode
---@field TODO nil # Figure out the fields

---@class NeotreeAutocmdArg
---@field id number # autocommand id
---@field event string # name of the triggered event `autocmd-events`
---@field group number`nil # autocommand group id, if any
---@field match string # expanded value of `<amatch>`
---@field buf number # expanded value of `<abuf>`
---@field file string # expanded value of `<afile>`
---@field data any # arbitrary data passed from `nvim_exec_autocmds()`

---@alias NeotreeTypes.sort_function fun(a: NeotreeNode, b: NeotreeNode): boolean
---@alias NeotreeConfig.highlight string # Name of a highlight group
---@alias NeotreeConfig.wh integer|string|nil
---@alias NeotreeConfig.log_level "trace"|"debug"|"info"|"warn"|"error"|"fatal"
---@alias NeotreeConfig.diagnostics_keys "hint"|"info"|"warn"|"error"
---@alias NeotreeConfig.components.align "left"|"right"
