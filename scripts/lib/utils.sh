#!/usr/bin/env bash

# Loophole Builder repository root (scripts/lib → ../..)
if [[ -z "${LOOPHOLE_BUILDER_ROOT:-}" ]]; then
  LOOPHOLE_BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  export LOOPHOLE_BUILDER_ROOT
fi

APP_NAME="${APP_NAME:-Loophole}"
APP_NAME_LC="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"
BINARY_NAME="${BINARY_NAME:-loophole}"
GH_REPO_PATH="${GH_REPO_PATH:-loophole-ai/loophole-ide}"
ORG_NAME="${ORG_NAME:-loophole-ai}"

echo "---------- utils.sh -----------"
echo "APP_NAME=\"${APP_NAME}\""
echo "APP_NAME_LC=\"${APP_NAME_LC}\""
echo "BINARY_NAME=\"${BINARY_NAME}\""
echo "GH_REPO_PATH=\"${GH_REPO_PATH}\""
echo "ORG_NAME=\"${ORG_NAME}\""

# All common functions can be added to this file

apply_patch() {
  if [[ -z "$2" ]]; then
    echo applying patch: "$1";
  fi
  # grep '^+++' "$1"  | sed -e 's#+++ [ab]/#./vscode/#' | while read line; do shasum -a 256 "${line}"; done

  cp $1{,.bak}

  replace "s|!!APP_NAME!!|${APP_NAME}|g" "$1"
  replace "s|!!APP_NAME_LC!!|${APP_NAME_LC}|g" "$1"
  replace "s|!!BINARY_NAME!!|${BINARY_NAME}|g" "$1"
  replace "s|!!GH_REPO_PATH!!|${GH_REPO_PATH}|g" "$1"
  replace "s|!!ORG_NAME!!|${ORG_NAME}|g" "$1"
  replace "s|!!RELEASE_VERSION!!|${RELEASE_VERSION}|g" "$1"

  # Upstream can rename/remove files (e.g. *.js -> *.ts).
  # If a patch targets missing files, skip it instead of failing the whole CI.
  local missing_targets=0
  while IFS= read -r target; do
    if [[ ! -f "${target}" ]]; then
      echo "Skipping patch ${1}: target not found (${target})" >&2
      missing_targets=1
    fi
  done < <(awk '/^\+\+\+ b\// { sub(/^\+\+\+ b\//, "", $0); print $0 }' "$1")

  if [[ "${missing_targets}" -eq 1 ]]; then
    mv -f $1{.bak,}
    return 0
  fi

  if ! git apply --ignore-whitespace "$1"; then
    echo "Skipping patch ${1}: context no longer matches upstream" >&2
    mv -f $1{.bak,}
    return 0
  fi

  mv -f $1{.bak,}
}

exists() { type -t "$1" &> /dev/null; }

is_gnu_sed() {
  sed --version &> /dev/null
}

replace() {
  if is_gnu_sed; then
    sed -i -E "${1}" "${2}"
  else
    sed -i '' -E "${1}" "${2}"
  fi
}

if ! exists gsed; then
  if is_gnu_sed; then
    function gsed() {
      sed -i -E "$@"
    }
  else
    function gsed() {
      sed -i '' -E "$@"
    }
  fi
fi

ensure_build_sourceversion() {
  if [[ -n "${BUILD_SOURCEVERSION}" ]]; then
    export BUILD_SOURCEVERSION
    return 0
  fi

  echo "Computing BUILD_SOURCEVERSION..."

  if [[ -d "./vscode" ]]; then
    BUILD_SOURCEVERSION=$(cd ./vscode && git rev-parse HEAD)
  else
    if ! command -v checksum &>/dev/null; then
      npm install -g checksum
    fi
    BUILD_SOURCEVERSION=$( echo "${RELEASE_VERSION/-*/}" | checksum )
  fi

  echo "BUILD_SOURCEVERSION=\"${BUILD_SOURCEVERSION}\""

  if [[ "${GITHUB_ENV}" ]]; then
    echo "BUILD_SOURCEVERSION=${BUILD_SOURCEVERSION}" >> "${GITHUB_ENV}"
  fi

  export BUILD_SOURCEVERSION
}
