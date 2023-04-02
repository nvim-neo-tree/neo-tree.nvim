local M = {}

-- TODO: move to config
M.kinds = {
  [1] = { name = "File", icon = "", hl = "Tag" },
  [2] = { name = "Module", icon = "", hl = "Exception" },
  [3] = { name = "Namespace", icon = "", hl = "Include" },
  [4] = { name = "Package", icon = "", hl = "Label" },
  [5] = { name = "Class", icon = "", hl = "Include" },
  [6] = { name = "Method", icon = "", hl = "Function" },
  [7] = { name = "Property", icon = "", hl = "@property" },
  [8] = { name = "Field", icon = "", hl = "@field" },
  [9] = { name = "Constructor", icon = "", hl = "@constructor" },
  [10] = { name = "Enum", icon = "了", hl = "@number" },
  [11] = { name = "Interface", icon = "", hl = "Type" },
  [12] = { name = "Function", icon = "", hl = "Function" },
  [13] = { name = "Variable", icon = "", hl = "@variable" },
  [14] = { name = "Constant", icon = "", hl = "Constant" },
  [15] = { name = "String", icon = "", hl = "String" },
  [16] = { name = "Number", icon = "", hl = "Number" },
  [17] = { name = "Boolean", icon = "", hl = "Boolean" },
  [18] = { name = "Array", icon = "", hl = "Type" },
  [19] = { name = "Object", icon = "", hl = "Type" },
  [20] = { name = "Key", icon = "", hl = "" },
  [21] = { name = "Null", icon = "", hl = "Constant" },
  [22] = { name = "EnumMember", icon = "", hl = "Number" },
  [23] = { name = "Struct", icon = "", hl = "Type" },
  [24] = { name = "Event", icon = "", hl = "Constant" },
  [25] = { name = "Operator", icon = "", hl = "Operator" },
  [26] = { name = "TypeParameter", icon = "", hl = "Type" },
}

M.get_kind = function(kind_id, default)
  return M.kinds[kind_id] or default or { name = "Unknown", icon = "?", hl = "" }
end

return M
