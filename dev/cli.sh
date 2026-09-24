#!/usr/bin/env bash
# Local helper for rebuilding the Loophole CLI and tunnel executable on macOS.

set -e

cd "$(dirname "${BASH_SOURCE[0]}")/../vscode/cli"

export VSCODE_CLI_APPLICATION_NAME="loophole"
export VSCODE_CLI_BINARY_NAME="loophole-server"
export VSCODE_CLI_NAME_LONG="Loophole"
export VSCODE_CLI_QUALITYLESS_PRODUCT_NAME="Loophole"
export VSCODE_CLI_QUALITY="stable"
export VSCODE_CLI_DATA_FOLDER_NAME=".loophole-editor"
export VSCODE_CLI_SERVER_DATA_FOLDER_NAME=".loophole-server"
export VSCODE_CLI_DOWNLOAD_URL="https://github.com/loophole-ai/loophole-ide/releases"
export VSCODE_CLI_UPDATE_URL="https://raw.githubusercontent.com/loophole-ai/versions/refs/heads/main"
export VSCODE_CLI_DOCUMENTATION_URL="https://loophole.dev"
export VSCODE_CLI_TUNNEL_EDITOR_WEB_URL="https://loophole.dev"

cargo build --release --target aarch64-apple-darwin --bin=code

cp target/aarch64-apple-darwin/release/code \
  "../../VSCode-darwin-arm64/Loophole.app/Contents/Resources/app/bin/loophole-tunnel"

"../../VSCode-darwin-arm64/Loophole.app/Contents/Resources/app/bin/loophole-tunnel" serve-web
