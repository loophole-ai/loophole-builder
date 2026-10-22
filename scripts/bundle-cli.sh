#!/usr/bin/env bash
#---------------------------------------------------------------------------------------
#  Copyright 2026 Loophole AI. All rights reserved.
#  Licensed under the AGPL-3.0 License. See LICENSE.txt for more information.
#---------------------------------------------------------------------------------------
#
# bundle-cli.sh <x64|arm64>
#
# Fetches the released Loophole CLI binary from npm and places it at
# vscode/resources/loophole-cli(.exe) so the packaging step ships it inside the
# install and the IDE can spawn the engine without a separately installed server.
#
# OS comes from $RUNNER_OS (Windows | macOS | Linux), arch from the first argument.
# npm must already be on PATH (CI installs and pins it right before this runs).
# Set LOOPHOLE_CLI_VERSION to pin a specific release; it defaults to latest.
# Set LOOPHOLE_IDE_ROOT to override the IDE checkout directory; it defaults to vscode.
set -euo pipefail

arch="${1:?'usage: bundle-cli.sh <x64|arm64>'}"
case "$arch" in
  x64 | arm64) ;;
  *) echo "::error::unsupported arch '$arch', expected x64 or arm64"; exit 1 ;;
esac

case "$RUNNER_OS" in
  Windows) os="windows"; binary="loophole.exe"; cli_name="loophole-cli.exe" ;;
  macOS) os="darwin"; binary="loophole"; cli_name="loophole-cli" ;;
  Linux) os="linux"; binary="loophole"; cli_name="loophole-cli" ;;
  *) echo "::error::unsupported RUNNER_OS '$RUNNER_OS'"; exit 1 ;;
esac

version="${LOOPHOLE_CLI_VERSION:-latest}"
ide_root="${LOOPHOLE_IDE_ROOT:-vscode}"
package="@loophole-ai/cli-${os}-${arch}@${version}"

workdir="./.loophole-cli-fetch"
rm -rf "$workdir"
mkdir -p "$workdir"

(
  cd "$workdir"
  npm pack "$package" --silent
  tarball=$(ls -1 ./*.tgz | head -n1 || { echo "::error::npm pack produced no tarball for $package"; exit 1; })
  tar -xzf "$tarball"
  binary_path=$(find . -type f -name "$binary" | head -n1 || true)
  if [[ -z "$binary_path" ]]; then
    echo "::error::$binary not found inside the $package tarball"
    find . -type f | head -n 40
    exit 1
  fi
  mkdir -p "$OLDPWD/$ide_root/resources"
  cp -f "$binary_path" "$OLDPWD/$ide_root/resources/$cli_name"
  if [[ "$os" != "windows" ]]; then
    chmod 755 "$OLDPWD/$ide_root/resources/$cli_name"
  fi
  size_mb=$(du -m "$OLDPWD/$ide_root/resources/$cli_name" | cut -f1)
  echo "Bundled CLI: $ide_root/resources/$cli_name (${size_mb} MB, from $package)"
)

rm -rf "$workdir"
