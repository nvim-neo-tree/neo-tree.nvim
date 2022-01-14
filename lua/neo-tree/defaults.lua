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
  open_files_in_last_window = true, -- false = open files in top left window
  log_level = "info", -- "trace", "debug", "info", "warn", "error", "fatal"
  log_to_file = false, -- true, false, "/path/to/file.log", use :NeoTreeLogs to show the file
  --open_files_in_last_window = true -- true = open files in last window visited
  --
  --event_handlers = {
  --  {
  --    event = "before_render",
  --    handler = function (state)
  --      -- add something to the state that can be used by custom components
  --    end
  --  },
  --  {
  --    event = "file_opened",
  --    handler = function(file_path)
  --      --auto close
  --      require("neo-tree").close_all()
  --    end
  --  },
  --  {
  --    event = "file_renamed",
  --    handler = function(args)
  --      -- fix references to file
  --      print(args.source, " renamed to ", args.destination)
  --    end
  --  },
  --  {
  --    event = "file_moved",
  --    handler = function(args)
  --      -- fix references to file
  --      print(args.source, " moved to ", args.destination)
  --    end
  --  },
  --}
}
return config
