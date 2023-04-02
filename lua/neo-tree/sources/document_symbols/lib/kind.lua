local M = {}

M.kind_names = {
  "File",
  "Module",
  "Namespace",
  "Package",
  "Class",
  "Method",
  "Property",
  "Field",
  "Constructor",
  "Enum",
  "Interface",
  "Function",
  "Variable",
  "Constant",
  "String",
  "Number",
  "Boolean",
  "Array",
  "Object",
  "Key",
  "Null",
  "EnumMember",
  "Struct",
  "Event",
  "Operator",
  "TypeParameter",
  "Component",
  "Fragment",
}

M.get_kind_name = function(kind_id, default)
  return M.kind_names[kind_id] or default or "Unknown"
end

return M
