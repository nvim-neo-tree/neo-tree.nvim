---Functions to render symbols' kinds
local M = {}

local kinds_id_to_name = {
  [0] = "Root",
  [1] = "File",
  [2] = "Module",
  [3] = "Namespace",
  [4] = "Package",
  [5] = "Class",
  [6] = "Method",
  [7] = "Property",
  [8] = "Field",
  [9] = "Constructor",
  [10] = "Enum",
  [11] = "Interface",
  [12] = "Function",
  [13] = "Variable",
  [14] = "Constant",
  [15] = "String",
  [16] = "Number",
  [17] = "Boolean",
  [18] = "Array",
  [19] = "Object",
  [20] = "Key",
  [21] = "Null",
  [22] = "EnumMember",
  [23] = "Struct",
  [24] = "Event",
  [25] = "Operator",
  [26] = "TypeParameter",
}

local kinds_map = {}

M.get_kind = function(kind_id)
  local kind_name = kinds_id_to_name[kind_id]
  return vim.tbl_extend(
    "force",
    { name = kind_name or ("Unknown: " .. kind_id), icon = "?", hl = "" },
    kind_name and (kinds_map[kind_name] or {}) or kinds_map["Unknown"]
  )
end

M.setup = function(custom_kinds, kinds)
  kinds_id_to_name = vim.tbl_deep_extend("force", kinds_id_to_name, custom_kinds or {})
  kinds_map = kinds
end

return M
