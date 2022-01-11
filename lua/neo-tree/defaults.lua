local config = {
  -- The default_source is the one used when calling require('neo-tree').show()
  -- without a source argument.
  default_source = "filesystem",
  -- popup_border_style is for input and confirmation dialogs.
  -- Configurtaion of floating window is done in the individual source sections.
  popup_border_style = "NC", -- "double", "none", "rounded", "shadow", "single" or "solid"
  -- "NC" is a special style that works well with NormalNC set
  enable_git_status = true,
  enable_diagnostics = true,
  open_files_in_last_window = true, -- false = open files int top left window
                                     -- true = open files in last window visited
}
return config
