# An example install script for people using `:h packages`
$NVIM_APPNAME = if ($env:NVIM_APPNAME) { $env:NVIM_APPNAME } else { "nvim" }

$NEOTREE_DATA_HOME = if ($env:XDG_DATA_HOME) {
    Join-Path $env:XDG_DATA_HOME $NVIM_APPNAME
} else {
    Join-Path $HOME ".local\share\$NVIM_APPNAME"
}

###########
# Options #
###########

# You can modify the /neo-tree*/ names here, depending on how you like to organize your packages.
$NEOTREE_DIR = Join-Path $NEOTREE_DATA_HOME "site\pack\neo-tree\start"
$NEOTREE_DEPS_DIR = Join-Path $NEOTREE_DATA_HOME "site\pack\neo-tree-deps\start"
$NEOTREE_OPTIONAL_DIR = Join-Path $NEOTREE_DATA_HOME "site\pack\neo-tree-optional\start"

# Modify the optional plugins you want below:
$OPTIONAL_PLUGINS = @(
    "https://github.com/nvim-tree/nvim-web-devicons.git"           # for file icons
    # "https://github.com/antosha417/nvim-lsp-file-operations.git" # for LSP-enhanced renames/etc.
    # "https://github.com/folke/snacks.nvim.git"                   # for image previews
    # "https://github.com/3rd/image.nvim.git"                      # for image previews
    # "https://github.com/s1n7ax/nvim-window-picker.git"           # for _with_window_picker keymaps
)

###########################
# The rest of the script. #
###########################

# Save the current directory
$ORIGINAL_DIR = Get-Location

function Invoke-GitCloneSparse {
    git clone --filter=blob:none @args
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git clone failed with exit code $LASTEXITCODE for arguments: $($args -join ' ')"
    }
}

New-Item -ItemType Directory -Path $NEOTREE_DIR, $NEOTREE_DEPS_DIR -Force | Out-Null

Write-Host "Installing neo-tree..."
Set-Location $NEOTREE_DIR
Invoke-GitCloneSparse -b v3.x "https://github.com/nvim-neo-tree/neo-tree.nvim.git"

Write-Host "Installing core dependencies..."
Set-Location $NEOTREE_DEPS_DIR
Invoke-GitCloneSparse "https://github.com/nvim-lua/plenary.nvim.git"
Invoke-GitCloneSparse "https://github.com/MunifTanjim/nui.nvim.git"

if ($OPTIONAL_PLUGINS.Count -gt 0) {
    Write-Host "Installing optional plugins..."
    New-Item -ItemType Directory -Path $NEOTREE_OPTIONAL_DIR -Force | Out-Null
    Set-Location $NEOTREE_OPTIONAL_DIR

    foreach ($repo in $OPTIONAL_PLUGINS) {
        Invoke-GitCloneSparse $repo
    }
}

Write-Host "Regenerating help tags..."
$PLUGIN_BASE_DIRS = @(
    $NEOTREE_DIR
    $NEOTREE_DEPS_DIR
    $NEOTREE_OPTIONAL_DIR
)

foreach ($base_dir in $PLUGIN_BASE_DIRS) {
    # Check if the base directory exists
    if (Test-Path $base_dir -PathType Container) {
        foreach ($doc_path in Get-ChildItem "$base_dir/*/doc" -Directory) {
            Write-Host "Generating helptags for: $doc_path"
            & nvim -u NONE --headless -c "helptags $doc_path" -c "q"
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Nvim helptags command failed for $doc_path. Exit code: $LASTEXITCODE"
            }
        }
    } else {
        Write-Host "Info: Base plugin directory not found, skipping for helptags: $base_dir"
    }
}

Write-Host "Installation complete!"
Set-Location $ORIGINAL_DIR
