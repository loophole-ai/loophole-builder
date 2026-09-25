#!/usr/bin/env bash
# CI library (sourced by ci_check.sh, ci_platform.sh). Do not execute directly.

ci_write_github_env() {
  if [[ ! "${GITHUB_ENV}" ]]; then
    return 0
  fi
  while [[ $# -gt 0 ]]; do
    echo "$1" >> "${GITHUB_ENV}"
    shift
  done
}

ci_git_safe_directory() {
  if [[ "${CI_BUILD}" != "no" ]]; then
    local repo_lower
    repo_lower=$( echo "${GITHUB_REPOSITORY}" | awk '{print tolower($0)}' )
    git config --global --add safe.directory "/__w/${repo_lower}"
    git config --global --add safe.directory "/__w/${repo_lower}/${repo_lower##*/}"
    if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
      git config --global --add safe.directory "${GITHUB_WORKSPACE}"
      git config --global --add safe.directory "${GITHUB_WORKSPACE}/vscode"
    fi
  fi
}

ci_check_cron_or_pr() {
  export INCREMENT_VERSION="${INCREMENT_VERSION:-no}"

  if [[ "${BUILD_ONLY:-no}" == "yes" ]]; then
    echo "Build-only test mode: deployment and version changes are disabled"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="no"
    export INCREMENT_VERSION="no"
    export GITHUB_BRANCH="${GITHUB_BRANCH:-${GITHUB_REF_NAME:-}}"

    ci_write_github_env \
      "GITHUB_BRANCH=${GITHUB_BRANCH}" \
      "SHOULD_BUILD=${SHOULD_BUILD}" \
      "SHOULD_DEPLOY=${SHOULD_DEPLOY}" \
      "VSCODE_QUALITY=${VSCODE_QUALITY:-stable}" \
      "INCREMENT_VERSION=${INCREMENT_VERSION}"
    return 0
  fi

  if [[ "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
    echo "It's a PR"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="no"
  elif [[ "${GITHUB_EVENT_NAME}" == "push" ]]; then
    echo "It's a Push"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="no"
  elif [[ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" ]]; then
    echo "It's a Dispatch"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="yes"
  else
    echo "It's a Cron"
    export SHOULD_BUILD="yes"
    export SHOULD_DEPLOY="yes"
  fi

  if [[ "${SHOULD_DEPLOY}" == "yes" ]]; then
    export INCREMENT_VERSION="yes"
  fi

  export GITHUB_BRANCH="${GITHUB_BRANCH:-${GITHUB_REF_NAME:-}}"

  ci_write_github_env \
    "GITHUB_BRANCH=${GITHUB_BRANCH}" \
    "SHOULD_BUILD=${SHOULD_BUILD}" \
    "SHOULD_DEPLOY=${SHOULD_DEPLOY}" \
    "VSCODE_QUALITY=${VSCODE_QUALITY:-stable}" \
    "INCREMENT_VERSION=${INCREMENT_VERSION:-no}"
}

ci_version_max() {
  printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1
}

# Base VS Code semver x.y.z (without .0 Inno, without -insider, without extra zeros like 1.99.030).
ci_normalize_ms_tag() {
  local v="${1%%-*}"

  if [[ "${v}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((10#${BASH_REMATCH[3]}))"
  elif [[ "${v}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((10#${BASH_REMATCH[3]}))"
  else
    echo "${v}"
  fi
}

# Inno Setup: VersionInfoVersion = x.y.z.w mandatory. Workaround: patch package.json
# only during Inno gulp tasks, then restore (see ci_restore_package_json_version).
ci_win_inno_version() {
  local base
  base="$(ci_normalize_ms_tag "${1}")"
  echo "${base}.0"
}

ci_apply_win_inno_package_version() {
  local ver="${1:-$(ci_win_inno_version "${MS_TAG:-${RELEASE_VERSION%%-*}}")}"
  local tmp

  if [[ ! -f package.json ]]; then
    echo "ci_apply_win_inno_package_version: package.json not found" >&2
    return 1
  fi

  tmp=$(mktemp)
  jq --arg v "${ver}" '.version = $v' package.json > "${tmp}"
  mv "${tmp}" package.json
  echo "Windows Inno package.json version=${ver} (app remains x.y.z after restore)"
}

ci_restore_package_json_version() {
  if [[ -f package.json.bak ]]; then
    cp package.json.bak package.json
    echo "Restored package.json version=$(jq -r '.version // empty' package.json)"
  fi
}

# Increment only patch (e.g. 1.5.3 → 1.5.4).
ci_bump_patch() {
  local version="${1}"
  local major minor patch

  if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Invalid semver for bump: ${version}" >&2
    return 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  patch=$((patch + 1))
  echo "${major}.${minor}.${patch}"
}

# Increment minor and reset patch to 0 (e.g. 1.5.3 → 1.6.0).
ci_bump_minor() {
  local version="${1}"
  local major minor

  if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Invalid semver for bump: ${version}" >&2
    return 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  minor=$((minor + 1))
  echo "${major}.${minor}.0"
}

ci_extract_loophole_version_from_tag() {
  local tag="${1#v}"

  if [[ "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-insider)?$ ]]; then
    echo "${tag%-insider}"
  fi
}

ci_latest_loophole_from_releases() {
  if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -z "${GH_TOKEN:-}" ]]; then
    return 0
  fi

  local tags loophole_part
  tags=$( gh release list --repo "${ASSETS_REPOSITORY}" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null || true )

  if [[ -z "${tags}" ]]; then
    return 0
  fi

  while IFS= read -r tag; do
    loophole_part=$(ci_extract_loophole_version_from_tag "${tag}")
    if [[ -n "${loophole_part}" ]]; then
      echo "${loophole_part}"
    fi
  done <<< "${tags}" | sort -V | tail -1
}

# Keep the built IDE metadata aligned with the version selected by the check job.
ci_apply_loophole_version() {
  if [[ -z "${LOOPHOLE_VERSION:-}" ]] || [[ ! -f vscode/product.json ]]; then
    return 0
  fi

  local current
  current=$( jq -r '.loopholeVersion // empty' vscode/product.json )
  [[ "${current}" == "null" ]] && current=""

  if [[ "${current}" == "${LOOPHOLE_VERSION}" ]]; then
    return 0
  fi

  echo "vscode/product.json loopholeVersion: ${current:-<empty>} -> ${LOOPHOLE_VERSION}"
  local tmp
  tmp=$(mktemp)
  jq --arg v "${LOOPHOLE_VERSION}" '.loopholeVersion = $v' vscode/product.json > "${tmp}"
  mv "${tmp}" vscode/product.json
}

ci_bump_version_write_env() {
  if [[ ! "${GITHUB_ENV}" ]]; then
    return 0
  fi

  echo "LOOPHOLE_VERSION=${LOOPHOLE_VERSION}" >> "${GITHUB_ENV}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
  {
    echo "RELEASE_TITLE<<GITHUB_RELEASE_TITLE"
    echo "${RELEASE_TITLE}"
    echo "GITHUB_RELEASE_TITLE"
  } >> "${GITHUB_ENV}"
}

ci_bump_version() {
  # A minor bump request always implies a bump, even if INCREMENT_VERSION was not set.
  if [[ "${INCREMENT_VERSION}" != "yes" && "${INCREMENT_MINOR}" != "yes" ]]; then
    echo "Version increment disabled (INCREMENT_VERSION != yes)"
    return 0
  fi

  if [[ -z "${LOOPHOLE_VERSION}" ]]; then
    echo "loopholeVersion is missing from the Loophole IDE product metadata" >&2
    return 1
  fi

  local latest_released base_version
  latest_released=$(ci_latest_loophole_from_releases || true)
  base_version="${LOOPHOLE_VERSION}"

  if [[ -n "${latest_released}" ]]; then
    base_version=$(ci_version_max "${LOOPHOLE_VERSION}" "${latest_released}")
    echo "Latest Loophole release on ${ASSETS_REPOSITORY}: ${latest_released} (bump base: ${base_version})"
  else
    echo "No prior Loophole release found on ${ASSETS_REPOSITORY}; bumping from ${base_version}"
  fi

  if [[ "${INCREMENT_MINOR}" == "yes" ]]; then
    LOOPHOLE_VERSION=$(ci_bump_minor "${base_version}")
  else
    LOOPHOLE_VERSION=$(ci_bump_patch "${base_version}")
  fi

  RELEASE_VERSION="${LOOPHOLE_VERSION}"
  RELEASE_TITLE="${LOOPHOLE_VERSION}"

  echo "Incremented loopholeVersion: ${base_version} -> ${LOOPHOLE_VERSION}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}"
  echo "RELEASE_TITLE=${RELEASE_TITLE}"

  ci_apply_loophole_version

  ci_bump_version_write_env
  export LOOPHOLE_VERSION RELEASE_VERSION RELEASE_TITLE
}

ci_ensure_gh_in_path() {
  if command -v gh &>/dev/null; then
    return 0
  fi
  local win_gh gh_dir
  for win_gh in \
    "/c/Program Files/GitHub CLI/gh.exe" \
    "/c/Program Files (x86)/GitHub CLI/gh.exe" \
    ; do
    if [[ -x "${win_gh}" ]]; then
      gh_dir=$(dirname "${win_gh}")
      export PATH="${gh_dir}:${PATH}"
      return 0
    fi
  done
  return 1
}

ci_install_gh_fetch_tag() {
  local api_url="https://api.github.com/repos/cli/cli/releases/latest"
  local -a curl_opts=(
    -sS
    --retry 5
    --retry-delay 10
    -H "Accept: application/vnd.github+json"
  )

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_opts+=( -H "Authorization: Bearer ${GITHUB_TOKEN}" )
  fi

  local TAG
  TAG="$( curl "${curl_opts[@]}" "$api_url" | jq --raw-output '.tag_name // empty' )"

  if [[ -z "${TAG}" || "${TAG}" == "null" ]]; then
    echo "Unable to get cli/cli latest via API; fallback to pinned version." >&2
    TAG="v2.74.0"
  fi
  echo "${TAG}"
}

ci_install_gh_add_to_path() {
  local install_dir="${1}"
  mkdir -p "${install_dir}"
  export PATH="${install_dir}:${PATH}"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${install_dir}" >> "${GITHUB_PATH}"
  fi
}

ci_install_gh() {
  set -ex

  if ci_ensure_gh_in_path; then
    echo "GitHub CLI is already available: $(gh --version | head -1)"
    return 0
  fi

  local TAG VERSION GH_ARCH="amd64"
  TAG="$(ci_install_gh_fetch_tag)"
  VERSION="${TAG#v}"

  local install_dir="${LOOPHOLE_BUILDER_ROOT:-${GITHUB_WORKSPACE:-${PWD}}}/.ci-bin"
  ci_install_gh_add_to_path "${install_dir}"

  if [[ "${OS_NAME}" == "windows" || "${RUNNER_OS}" == "Windows" ]]; then
    local archive="gh_${VERSION}_windows_${GH_ARCH}.zip"
    curl --retry 12 --retry-delay 120 -sSL -f \
      "https://github.com/cli/cli/releases/download/${TAG}/${archive}" \
      -o "${archive}"
    unzip -q -o "${archive}"
    install -m 755 "gh_${VERSION}_windows_${GH_ARCH}/bin/gh.exe" "${install_dir}/gh.exe"
    ln -sf gh.exe "${install_dir}/gh" 2>/dev/null || cp "${install_dir}/gh.exe" "${install_dir}/gh"
  else
    local archive="gh_${VERSION}_linux_${GH_ARCH}.tar.gz"
    curl --retry 12 --retry-delay 120 -sSL -f \
      "https://github.com/cli/cli/releases/download/${TAG}/${archive}" \
      -o "${archive}"
    tar xf "${archive}"
    install -m 755 "gh_${VERSION}_linux_${GH_ARCH}/bin/gh" "${install_dir}/gh"
  fi

  gh --version
}

ci_check_tags() {
  if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
    echo "Will not build because no GITHUB_TOKEN defined"
    return 0
  fi

  GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"
  GH_HOST="${GH_HOST:-github.com}"

  echo "Platform build flags (preserve SHOULD_BUILD/SHOULD_DEPLOY from check job when set)"
  export SHOULD_BUILD="${SHOULD_BUILD:-yes}"
  export SHOULD_DEPLOY="${SHOULD_DEPLOY:-yes}"

  export SHOULD_BUILD_APPIMAGE="yes"
  export SHOULD_BUILD_DEB="yes"
  export SHOULD_BUILD_DMG="yes"
  export SHOULD_BUILD_EXE_SYS="yes"
  export SHOULD_BUILD_EXE_USR="yes"
  export SHOULD_BUILD_MSI="yes"
  export SHOULD_BUILD_MSI_NOUP="yes"
  export SHOULD_BUILD_REH="yes"
  export SHOULD_BUILD_REH_WEB="yes"
  export SHOULD_BUILD_RPM="yes"
  export SHOULD_BUILD_TAR="yes"
  export SHOULD_BUILD_ZIP="yes"

  if [[ "${IS_SPEARHEAD}" == "yes" ]]; then
    export SHOULD_BUILD_SRC="no"
  elif [[ "${OS_NAME}" == "linux" ]]; then
    if [[ "${VSCODE_ARCH}" == "ppc64le" || "${VSCODE_ARCH}" == "riscv64" || "${VSCODE_ARCH}" == "loong64" ]]; then
      export SHOULD_BUILD_DEB="no"
      export SHOULD_BUILD_RPM="no"
    fi
    if [[ "${VSCODE_ARCH}" != "x64" || "${DISABLE_APPIMAGE}" == "yes" ]]; then
      export SHOULD_BUILD_APPIMAGE="no"
    fi
  elif [[ "${OS_NAME}" == "windows" ]]; then
    if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
      export SHOULD_BUILD_REH="no"
      export SHOULD_BUILD_REH_WEB="no"
    fi
    if [[ "${DISABLE_MSI}" == "yes" ]]; then
      export SHOULD_BUILD_MSI="no"
      export SHOULD_BUILD_MSI_NOUP="no"
    fi
  fi

  # Do not re-enable DEB, RPM, or AppImage builds when the Linux workflow intentionally disabled them.
  if [[ "${OS_NAME}" == "linux" && "${SHOULD_BUILD_DEB}" == "no" ]]; then
    export SHOULD_BUILD_DEB="no"
    export SHOULD_BUILD_RPM="no"
    export SHOULD_BUILD_APPIMAGE="no"
  fi

  ci_write_github_env \
    "SHOULD_BUILD=${SHOULD_BUILD}" \
    "SHOULD_DEPLOY=${SHOULD_DEPLOY}" \
    "SHOULD_BUILD_APPIMAGE=${SHOULD_BUILD_APPIMAGE}" \
    "SHOULD_BUILD_DEB=${SHOULD_BUILD_DEB}" \
    "SHOULD_BUILD_DMG=${SHOULD_BUILD_DMG}" \
    "SHOULD_BUILD_EXE_SYS=${SHOULD_BUILD_EXE_SYS}" \
    "SHOULD_BUILD_EXE_USR=${SHOULD_BUILD_EXE_USR}" \
    "SHOULD_BUILD_MSI=${SHOULD_BUILD_MSI}" \
    "SHOULD_BUILD_MSI_NOUP=${SHOULD_BUILD_MSI_NOUP}" \
    "SHOULD_BUILD_REH=${SHOULD_BUILD_REH}" \
    "SHOULD_BUILD_REH_WEB=${SHOULD_BUILD_REH_WEB}" \
    "SHOULD_BUILD_RPM=${SHOULD_BUILD_RPM}" \
    "SHOULD_BUILD_TAR=${SHOULD_BUILD_TAR}" \
    "SHOULD_BUILD_ZIP=${SHOULD_BUILD_ZIP}" \
    "SHOULD_BUILD_SRC=${SHOULD_BUILD_SRC}"
}
