#!/usr/bin/env bash
# shellcheck disable=SC2129
# Clone the Loophole IDE source and optionally check out a builder pull request.
# Usage: ./ci_repo.sh [pr|ide|all]

set -e

# Resolve the builder root before changing into the IDE source directory.
BUILDER_REPO_ROOT="${LOOPHOLE_BUILDER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export LOOPHOLE_BUILDER_ROOT="${BUILDER_REPO_ROOT}"

ci_git_safe_directory() {
  if [[ "${CI_BUILD}" != "no" && -n "${GITHUB_REPOSITORY:-}" ]]; then
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

ci_repo_pr() {
  ci_git_safe_directory

  if [[ -n "${PULL_REQUEST_ID:-}" ]]; then
    local branch_name
    branch_name=$( git rev-parse --abbrev-ref HEAD )
    local github_username="${GITHUB_USERNAME:-github-actions[bot]}"

    git config --global user.email "$( echo "${github_username}" | awk '{print tolower($0)}' )-ci@not-real.com"
    git config --global user.name "${github_username} CI"
    if [[ -f .git/shallow ]]; then
      git fetch --unshallow
    fi
    git fetch origin "pull/${PULL_REQUEST_ID}/head"
    git checkout FETCH_HEAD
    git merge --no-edit "origin/${branch_name}"
  fi
}

ci_repo_loophole_ide() {
  echo "----------- ci_repo Loophole IDE -----------"
  echo "CI_BUILD=${CI_BUILD:-}"
  echo "GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-}"
  echo "RELEASE_VERSION=${RELEASE_VERSION:-}"
  echo "VSCODE_QUALITY=${VSCODE_QUALITY:-stable}"
  echo "SHOULD_DEPLOY=${SHOULD_DEPLOY:-}"
  echo "SHOULD_BUILD=${SHOULD_BUILD:-}"

  ci_git_safe_directory

  local ide_repo ide_branch
  ide_repo="${LOOPHOLE_IDE_REPO:-${GH_REPO_PATH:-loophole-ai/loophole-ide}}"

  if [[ -z "${LOOPHOLE_IDE_BRANCH:-}" ]]; then
    ide_branch=$( git ls-remote --symref "https://github.com/${ide_repo}.git" HEAD 2>/dev/null | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }' )
  else
    ide_branch="${LOOPHOLE_IDE_BRANCH}"
  fi
  ide_branch="${ide_branch:-main}"

  echo "Cloning Loophole IDE ${ide_repo} (${ide_branch})..."

  mkdir -p vscode
  cd vscode || { echo "'vscode' directory not found"; exit 1; }

  # Missing remote LFS objects must not prevent the source checkout.
  export GIT_LFS_SKIP_SMUDGE=1

  git init -q
  if git remote get-url origin &>/dev/null; then
    git remote set-url origin "https://github.com/${ide_repo}.git"
  else
    git remote add origin "https://github.com/${ide_repo}.git"
  fi
  git config --global --add safe.directory "$(pwd)"

  if [[ -n "${LOOPHOLE_IDE_COMMIT:-}" ]]; then
    echo "Using explicit Loophole IDE commit ${LOOPHOLE_IDE_COMMIT}"
    git fetch --depth 1 origin "${LOOPHOLE_IDE_COMMIT}"
    git checkout "${LOOPHOLE_IDE_COMMIT}"
  else
    git fetch --depth 1 origin "${ide_branch}"
    git checkout FETCH_HEAD
  fi

  MS_VERSION=$( jq -r '.version' package.json )
  # shellcheck source=scripts/lib/ci_lib.sh
  source "${BUILDER_REPO_ROOT}/scripts/lib/ci_lib.sh"
  MS_TAG=$(ci_normalize_ms_tag "${MS_VERSION}")
  MS_VERSION="${MS_TAG}"
  MS_COMMIT=$( git rev-parse HEAD )

  local pin_versions=false
  if [[ -n "${RELEASE_VERSION:-}" && -n "${LOOPHOLE_VERSION:-}" ]]; then
    pin_versions=true
    echo "Keeping pinned versions RELEASE_VERSION=${RELEASE_VERSION} LOOPHOLE_VERSION=${LOOPHOLE_VERSION}"
    RELEASE_TITLE="${RELEASE_TITLE:-${LOOPHOLE_VERSION}}"
  else
    LOOPHOLE_VERSION=$( jq -r '.loopholeVersion // empty' product.json )
    [[ "${LOOPHOLE_VERSION}" == "null" ]] && LOOPHOLE_VERSION=""

    if [[ ! "${LOOPHOLE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Loophole IDE product.json does not contain a valid loopholeVersion" >&2
      exit 1
    fi

    RELEASE_VERSION="${LOOPHOLE_VERSION}"
    RELEASE_TITLE="${LOOPHOLE_VERSION}"
  fi

  ci_apply_loophole_version

  echo "RELEASE_TITLE=\"${RELEASE_TITLE}\""
  echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""
  echo "LOOPHOLE_VERSION=\"${LOOPHOLE_VERSION}\""
  echo "MS_COMMIT=\"${MS_COMMIT}\""
  echo "MS_VERSION=\"${MS_VERSION}\""
  echo "MS_TAG=\"${MS_TAG}\""

  cd ..

  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "MS_TAG=${MS_TAG}" >> "${GITHUB_ENV}"
    echo "MS_COMMIT=${MS_COMMIT}" >> "${GITHUB_ENV}"
    if [[ "${pin_versions}" != "true" ]]; then
      echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
      echo "LOOPHOLE_VERSION=${LOOPHOLE_VERSION}" >> "${GITHUB_ENV}"
      {
        echo "RELEASE_TITLE<<GITHUB_RELEASE_TITLE"
        echo "${RELEASE_TITLE}"
        echo "GITHUB_RELEASE_TITLE"
      } >> "${GITHUB_ENV}"
    fi
  fi

  export MS_TAG MS_COMMIT RELEASE_VERSION RELEASE_TITLE LOOPHOLE_VERSION
}

ci_repo_run() {
  local mode="${1:-all}"
  case "${mode}" in
    pr) ci_repo_pr ;;
    ide) ci_repo_loophole_ide ;;
    all) ci_repo_pr; ci_repo_loophole_ide ;;
    *)
      echo "Usage: $0 [pr|ide|all]" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ci_repo_run "${1:-all}"
else
  [[ $# -gt 0 ]] && ci_repo_run "$@"
fi
