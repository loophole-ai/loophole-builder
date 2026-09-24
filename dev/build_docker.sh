#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

export APP_NAME="Loophole"
export BINARY_NAME="loophole"
export CI_BUILD="no"
export OS_NAME="linux"
export SHOULD_BUILD="yes"
export SKIP_ASSETS="yes"
export VSCODE_QUALITY="stable"

while getopts ":ip" opt; do
  case "$opt" in
    i)
      export VSCODE_QUALITY="insider"
      ;;
    p)
      export SKIP_ASSETS="no"
      ;;
    *)
      ;;
  esac
done

UNAME_ARCH=$( uname -m )

if [[ "${UNAME_ARCH}" == "x86_64" ]]; then
  export VSCODE_ARCH="x64"
else
  export npm_config_arch=armv7l
  export npm_config_force_process_config="true"
  export VSCODE_ARCH="armhf"
fi

echo "OS_NAME=\"${OS_NAME}\""
echo "SKIP_ASSETS=\"${SKIP_ASSETS}\""
echo "VSCODE_ARCH=\"${VSCODE_ARCH}\""
echo "VSCODE_QUALITY=\"${VSCODE_QUALITY}\""

rm -rf vscode* VSCode*

# shellcheck source=ci_repo.sh
. "${REPO_ROOT}/ci_repo.sh" ide
. build.sh

if [[ "${SKIP_ASSETS}" == "no" ]]; then
  . prepare_assets.sh
fi
