#!/usr/bin/env bash
# An example install script for people using `:h packages`
export NEOTREE_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/${NVIM_APPNAME:-nvim}"

###########
# Options #
###########

# You can modify the /neo-tree*/ names here, depending on how you like to organize your packages.
export NEOTREE_DIR="${NEOTREE_DATA_HOME}/site/pack/neo-tree/start"
export NEOTREE_DEPS_DIR="${NEOTREE_DATA_HOME}/site/pack/neo-tree-deps/start"
export NEOTREE_OPTIONAL_DIR="${NEOTREE_DATA_HOME}/site/pack/neo-tree-optional/start"

# Modify the optional plugins you want below:
declare -a OPTIONAL_PLUGINS=(
  "https://github.com/nvim-tree/nvim-web-devicons.git"            # for file icons
  # "https://github.com/antosha417/nvim-lsp-file-operations.git"  # for LSP-enhanced renames/etc.
  # "https://github.com/folke/snacks.nvim.git"                    # for image previews
  # "https://github.com/3rd/image.nvim.git"                       # for image previews
  # "https://github.com/s1n7ax/nvim-window-picker.git"            # for _with_window_picker keymaps
)

###########################
# The rest of the script. #
###########################

ORIGINAL_DIR="$(pwd)"

clone_sparse() {
  git clone --filter=blob:none "$@"
}

mkdir -p "${NEOTREE_DIR}" "${NEOTREE_DEPS_DIR}"

echo "Installing neo-tree..."
cd "${NEOTREE_DIR}"
clone_sparse -b v3.x https://github.com/nvim-neo-tree/neo-tree.nvim.git

echo "Installing core dependencies..."
cd "${NEOTREE_DEPS_DIR}"
clone_sparse https://github.com/nvim-lua/plenary.nvim.git
clone_sparse https://github.com/MunifTanjim/nui.nvim.git

if [ ${#OPTIONAL_PLUGINS[@]} -gt 0 ]; then
  echo "Installing optional plugins..."
  mkdir -p "${NEOTREE_OPTIONAL_DIR}"
  cd "${NEOTREE_OPTIONAL_DIR}"

  for repo in "${OPTIONAL_PLUGINS[@]}"; do
    clone_sparse "$repo"
  done
fi

echo "Regenerating help tags..."
declare -a PLUGIN_BASE_DIRS=(
  "${NEOTREE_DIR}"
  "${NEOTREE_DEPS_DIR}"
  "${NEOTREE_OPTIONAL_DIR}"
)

# Loop through each base directory and find all 'doc' subdirectories using glob
shopt -s nullglob # Enable nullglob for safe globbing (empty array if no matches)
for base_dir in "${PLUGIN_BASE_DIRS[@]}"; do
  # Check if the base directory exists
  if [ -d "$base_dir" ]; then
    for doc_path in "${base_dir}"/*/doc; do
      nvim -u NONE --headless -c "helptags ${doc_path}" -c "q"
    done
  fi
done
shopt -u nullglob # Disable nullglob

echo "Installation complete!"
cd "${ORIGINAL_DIR}"
