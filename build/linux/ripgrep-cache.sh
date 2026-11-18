#!/usr/bin/env bash
# Fetch the ripgrep binaries once on the host so @vscode/ripgrep's postinstall
# inside the build container (and the host npm ci) never hits the GitHub API at
# all. The postinstall checks $TMPDIR/vscode-ripgrep-cache-<version>/<asset>
# before calling the API — if it is present it is used as-is.

# Note: sourced by package_reh.sh — do not enable set -u here or it leaks into the caller.

VSCODE_HOST_MOUNT="${VSCODE_HOST_MOUNT:-${PWD}}"
RG_CACHE_ROOT="${VSCODE_HOST_MOUNT}/.build/ripgrep-cache"
RG_CACHE_DIR="${RG_CACHE_ROOT}/vscode-ripgrep-cache-1.17.1"

mkdir -p "${RG_CACHE_DIR}"

download() {
  local target="$1"
  local asset="ripgrep-v15.0.1-${target}.tar.gz"
  local url="https://github.com/microsoft/ripgrep-prebuilt/releases/download/v15.0.1/${asset}"
  local dest="${RG_CACHE_DIR}/${asset}"

  if [[ -s "${dest}" ]]; then
    echo "ripgrep cache present: ${dest}"
    return 0
  fi

  echo "Downloading ${url}"
  curl --fail --location --retry 5 --retry-delay 30 --retry-all-errors -sSL "${url}" -o "${dest}"
}

case "${VSCODE_ARCH:-x64}" in
  x64)   download "x86_64-unknown-linux-musl" ;;
  arm64) download "aarch64-unknown-linux-musl" ;;
  *)     echo "No ripgrep cache for VSCODE_ARCH=${VSCODE_ARCH:-?}; skipping" ;;
esac

# Export so every later npm ci (host and container via the patch mount) sees the cache.
export TMPDIR="${RG_CACHE_ROOT}"
