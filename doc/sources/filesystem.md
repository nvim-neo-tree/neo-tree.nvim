# Filesystem

A tree view of files on disk.

![Neo-tree file system](https://github.com/nvim-neo-tree/resources/raw/main/images/Neo-tree-filesystem.png)

# Options

```lua
filesystem = {
  window = {
    position = "left",
    width = 40,
    mappings = {
      ["<2-LeftMouse>"] = "open",
      ["<cr>"] = "open",
      ["S"] = "open_split",
      ["s"] = "open_vsplit",
      ["C"] = "close_node",
      ["<bs>"] = "navigate_up",
      ["."] = "set_root",
      ["H"] = "toggle_hidden",
      ["I"] = "toggle_gitignore",
      ["R"] = "refresh",
      ["/"] = "filter_as_you_type",
      ["f"] = "filter_on_submit",
      ["<c-x>"] = "clear_filter",
      ["a"] = "add",
      ["d"] = "delete",
      ["r"] = "rename",
      ["c"] = "copy_to_clipboard",
      ["x"] = "cut_to_clipboard",
      ["p"] = "paste_from_clipboard",
    }
  }
}
```
