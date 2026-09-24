#!/usr/bin/env bash
# shellcheck disable=SC1091
# Single entry point for the CI check job: policy, version, release, and build flags.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/ci_lib.sh
source "${REPO_ROOT}/scripts/lib/ci_lib.sh"

echo "=== CI check ==="

ci_check_cron_or_pr

if [[ "${SHOULD_BUILD}" == "yes" && "${SHOULD_DEPLOY}" == "yes" ]]; then
  ci_install_gh
fi

if [[ "${INCREMENT_VERSION}" == "yes" && "${SKIP_VERSION_BUMP}" != "yes" ]]; then
  ci_bump_version
fi

if [[ "${SHOULD_BUILD}" == "yes" && "${SHOULD_DEPLOY}" == "yes" ]]; then
  STRONGER_GITHUB_TOKEN="${STRONGER_GITHUB_TOKEN:-}" GITHUB_TOKEN="${GITHUB_TOKEN:-}" ./release.sh --create-only
fi

ci_check_tags

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "MS_COMMIT=${MS_COMMIT}"
    echo "MS_TAG=${MS_TAG}"
    echo "RELEASE_VERSION=${RELEASE_VERSION}"
    echo "LOOPHOLE_VERSION=${LOOPHOLE_VERSION}"
    echo "SHOULD_BUILD=${SHOULD_BUILD}"
    echo "SHOULD_DEPLOY=${SHOULD_DEPLOY}"
    echo "BUILD_ONLY=${BUILD_ONLY:-no}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "=== CI check done ==="
echo "RELEASE_VERSION=${RELEASE_VERSION} LOOPHOLE_VERSION=${LOOPHOLE_VERSION}"
