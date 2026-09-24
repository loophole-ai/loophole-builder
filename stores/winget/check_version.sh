#!/usr/bin/env bash

set -e

APP_IDENTIFIER="${APP_IDENTIFIER:-LoopholeAI.Loophole}"
MANIFEST_PATH="${APP_IDENTIFIER//.//}"
VERSIONS=$(curl --fail --silent --show-error \
  "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/v/${MANIFEST_PATH}")

if [[ "${VSCODE_QUALITY:-stable}" == "insider" ]]; then
  RELEASE_VERSION="${RELEASE_VERSION/-insider/}"
fi

WINGET_VERSION=$(echo "${VERSIONS}" | jq -r '
  map(.name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))) |
  sort_by(split(".") | map(tonumber)) |
  last // ""
')

echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""
echo "WINGET_VERSION=\"${WINGET_VERSION}\""

if [[ "${RELEASE_VERSION}" == "${WINGET_VERSION}" ]]; then
  export SHOULD_DEPLOY="no"
else
  export SHOULD_DEPLOY="yes"
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
  echo "SHOULD_DEPLOY=${SHOULD_DEPLOY}" >> "${GITHUB_ENV}"
fi
