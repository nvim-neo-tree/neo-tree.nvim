#!/usr/bin/env bash

set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --clean)
      shift
      echo "[test] cleaning up environment"
      rm -rf ./.testcache
      echo "[test] envionment cleaned"
      ;;
    *)
      shift
      ;;
  esac
done

function setup_environment() {
  echo
  echo "[test] setting up environment"
  echo

  local plugins_dir="./.testcache/site/pack/vendor/start"
  if [[ ! -d "${plugins_dir}" ]]; then
    mkdir -p "${plugins_dir}"
  fi

  if [[ ! -d "${plugins_dir}/nui.nvim" ]]; then
    echo "[plugins] nui.nvim: installing..."
    git clone https://github.com/MunifTanjim/nui.nvim "${plugins_dir}/nui.nvim"
    echo "[plugins] nui.nvim: installed"
    echo
  fi

  if [[ ! -d "${plugins_dir}/plenary.nvim" ]]; then
    echo "[plugins] plenary.nvim: installing..."
    git clone https://github.com/nvim-lua/plenary.nvim "${plugins_dir}/plenary.nvim"
    echo "[plugins] plenary.nvim: installed"
    echo
  fi

  echo "[test] environment ready"
  echo
}

setup_environment

make test
