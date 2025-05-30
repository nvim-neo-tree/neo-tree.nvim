local M = {}
-- diff keys of tables
function M.get_table_keys(name, tbl)
  local paths = {}

  local function traverse(current_name, current_table)
    for k, v in pairs(current_table) do
      local path_segment
      if type(k) == "number" then
        -- For numerical keys (array-like), use bracket notation
        path_segment = string.format("[%d]", k)
      else
        -- For string keys (dictionary-like), use dot notation
        path_segment = tostring(k)
      end

      local new_path
      if current_name == "" then
        new_path = path_segment
      else
        if type(k) == "number" then
          new_path = current_name .. path_segment
        else
          new_path = current_name .. "." .. path_segment
        end
      end

      if type(v) == "table" then
        -- If the value is a table, recurse
        traverse(new_path, v)
      else
        -- If it's a non-table value, add the path to our list
        table.insert(paths, new_path)
      end
    end
  end

  -- Start the traversal with the initial name and table
  traverse(name, tbl)

  -- Sort the paths alphabetically
  table.sort(paths)

  return paths
end

return M
