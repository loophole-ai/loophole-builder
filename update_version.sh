#!/usr/bin/env bash
# Publish release metadata to the Loophole versions repository.

set -e

loophole_version="${LOOPHOLE_VERSION:-${RELEASE_VERSION:-}}"
[[ "${loophole_version}" == "null" ]] && loophole_version=""
loophole_version="${loophole_version#v}"
loophole_version="${loophole_version%-insider}"
APP_NAME="${APP_NAME:-Loophole}"
VERSIONS_REPOSITORY="${VERSIONS_REPOSITORY:-loophole-ai/versions}"
VERSIONS_BRANCH="${VERSIONS_BRANCH:-main}"

if [[ "${SHOULD_BUILD:-no}" != "yes" && "${FORCE_UPDATE:-false}" != "true" ]]; then
  echo "Skipping versions update because this job did not build a release"
  exit 0
fi

if [[ -z "${RELEASE_VERSION:-}" ]]; then
  if [[ -f VERSION ]]; then
    RELEASE_VERSION=$(cat VERSION)
  else
    echo "RELEASE_VERSION is required" >&2
    exit 1
  fi
fi
loophole_version="${loophole_version:-${RELEASE_VERSION#v}}"
loophole_version="${loophole_version%-insider}"
if [[ ! "${loophole_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid Loophole version: ${loophole_version}" >&2
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" && -z "${GITHUB_ENTERPRISE_TOKEN:-}" && -z "${GH_ENTERPRISE_TOKEN:-}" ]]; then
  echo "Skipping versions update because no GitHub token is available"
  exit 0
fi

GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"
export GITHUB_TOKEN
export GH_TOKEN="${GITHUB_TOKEN}"
GH_HOST="${GH_HOST:-github.com}"
GITHUB_USERNAME="${GITHUB_USERNAME:-github-actions[bot]}"
VERSIONS_DIR_NAME=".versions-repo"
BUILDER_ROOT="${LOOPHOLE_BUILDER_ROOT:-$(pwd)}"
VERSIONS_DIR="${BUILDER_ROOT}/${VERSIONS_DIR_NAME}"
ASSETS_DIR="${BUILDER_ROOT}/assets"

if [[ ! -d "${ASSETS_DIR}" ]]; then
  echo "Assets directory not found: ${ASSETS_DIR}" >&2
  exit 1
fi

rm -rf "${VERSIONS_DIR}"
echo "Cloning ${VERSIONS_REPOSITORY} (${VERSIONS_BRANCH})"
GIT_LFS_SKIP_SMUDGE=1 git clone --branch "${VERSIONS_BRANCH}" --single-branch \
  "https://${GH_HOST}/${VERSIONS_REPOSITORY}.git" "${VERSIONS_DIR}"

git -C "${VERSIONS_DIR}" config user.email "$(echo "${GITHUB_USERNAME}" | awk '{print tolower($0)}')-ci@not-real.com"
git -C "${VERSIONS_DIR}" config user.name "${GITHUB_USERNAME} CI"
git -C "${VERSIONS_DIR}" remote set-url origin \
  "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@${GH_HOST}/${VERSIONS_REPOSITORY}.git"

URL_BASE="https://${GH_HOST}/${ASSETS_REPOSITORY}/releases/download/${RELEASE_VERSION}"

transform_version() {
  local version="${1#v}"
  version="${version%-insider}"

  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid Loophole release version: ${version}" >&2
    return 1
  fi

  echo "${version}"
}

calculate_sha256() {
  local file="$1"

  if command -v sha256sum &>/dev/null; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "${file}" | awk '{print $1}'
  elif [[ "${OS_NAME:-}" == "windows" ]] && command -v certutil &>/dev/null; then
    certutil -hashfile "${file}" SHA256 | awk 'NR==2 {print $1}'
  else
    echo "No SHA-256 utility is available" >&2
    return 1
  fi
}

generate_json() {
  local url name version product_version sha256hash timestamp asset_path

  url="${URL_BASE}/${ASSET_NAME}"
  name="${RELEASE_VERSION}"
  version="${loophole_version}"
  product_version=$(transform_version "${RELEASE_VERSION}") || return 1
  timestamp=$(node -e 'console.log(Date.now())')
  asset_path="${ASSETS_DIR}/${ASSET_NAME}"

  if [[ ! -f "${asset_path}" ]]; then
    echo "Downloading ${ASSET_NAME} from ${ASSETS_REPOSITORY}@${RELEASE_VERSION}"
    gh release download --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" \
      --dir "${ASSETS_DIR}" --pattern "${ASSET_NAME}"
  fi

  if [[ ! -f "${asset_path}" ]]; then
    echo "Required release asset not found: ${ASSET_NAME}" >&2
    return 1
  fi

  if [[ -f "${asset_path}.sha256" ]]; then
    sha256hash=$(awk '{print $1}' "${asset_path}.sha256")
  else
    sha256hash=$(calculate_sha256 "${asset_path}")
    echo "${sha256hash}" > "${asset_path}.sha256"
  fi

  if [[ -z "${url}" || -z "${name}" || -z "${version}" || -z "${product_version}" || -z "${timestamp}" || -z "${sha256hash}" ]]; then
    echo "Generated versions metadata contains an empty required field" >&2
    return 1
  fi

  jq -n \
    --arg url "${url}" \
    --arg name "${name}" \
    --arg version "${version}" \
    --arg productVersion "${product_version}" \
    --argjson timestamp "${timestamp}" \
    --arg sha256hash "${sha256hash}" \
    '{url: $url, name: $name, version: $version, productVersion: $productVersion, timestamp: $timestamp, sha256hash: $sha256hash}'
}

update_latest_version() {
  local current_version

  echo "Updating ${VERSION_PATH}/latest.json"

  if [[ -f "${VERSIONS_DIR}/${VERSION_PATH}/latest.json" ]]; then
    current_version=$(jq -r '.version // .name // empty' "${VERSIONS_DIR}/${VERSION_PATH}/latest.json")
    if [[ "${current_version}" == "${RELEASE_VERSION}" && "${FORCE_UPDATE:-false}" != "true" ]]; then
      echo "${VERSION_PATH} already points to ${RELEASE_VERSION}"
      return 0
    fi
  fi

  JSON_DATA=$(generate_json)
  mkdir -p "${VERSIONS_DIR}/${VERSION_PATH}"
  printf '%s\n' "${JSON_DATA}" > "${VERSIONS_DIR}/${VERSION_PATH}/latest.json"
  printf '%s\n' "${JSON_DATA}"
}

case "${OS_NAME:-}" in
  osx)
    ASSET_NAME="${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.dmg"
    VERSION_PATH="${VSCODE_QUALITY:-stable}/darwin/${VSCODE_ARCH}"
    update_latest_version
    ;;
  windows)
    ASSET_NAME="${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
    VERSION_PATH="${VSCODE_QUALITY:-stable}/win32/${VSCODE_ARCH}/system"
    update_latest_version

    ASSET_NAME="${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
    VERSION_PATH="${VSCODE_QUALITY:-stable}/win32/${VSCODE_ARCH}/user"
    update_latest_version

    ASSET_NAME="${APP_NAME}-win32-${VSCODE_ARCH}-${RELEASE_VERSION}.zip"
    VERSION_PATH="${VSCODE_QUALITY:-stable}/win32/${VSCODE_ARCH}/archive"
    update_latest_version

    if [[ "${VSCODE_ARCH}" == "x64" || "${VSCODE_ARCH}" == "ia32" ]]; then
      ASSET_NAME="${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}.msi"
      VERSION_PATH="${VSCODE_QUALITY:-stable}/win32/${VSCODE_ARCH}/msi"
      update_latest_version

      ASSET_NAME="${APP_NAME}-${VSCODE_ARCH}-updates-disabled-${RELEASE_VERSION}.msi"
      VERSION_PATH="${VSCODE_QUALITY:-stable}/win32/${VSCODE_ARCH}/msi-updates-disabled"
      update_latest_version
    fi
    ;;
  linux)
    ASSET_NAME="${APP_NAME}-linux-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz"
    VERSION_PATH="${VSCODE_QUALITY:-stable}/linux/${VSCODE_ARCH}"
    update_latest_version
    ;;
  *)
    echo "No versions metadata is defined for OS_NAME=${OS_NAME:-<empty>}" >&2
    exit 1
    ;;
esac

if [[ "${WRITE_VERSION_FILE:-no}" == "yes" ]]; then
  echo "${RELEASE_VERSION}" > "${VERSIONS_DIR}/VERSION"
fi

git -C "${VERSIONS_DIR}" add -A

if git -C "${VERSIONS_DIR}" diff --cached --quiet; then
  echo "No versions metadata changes to commit"
  exit 0
fi

build_number="${GITHUB_RUN_NUMBER:-local}"
git -C "${VERSIONS_DIR}" commit -m "CI update: Loophole ${RELEASE_VERSION} (build ${build_number})"

for attempt in 1 2 3; do
  if git -C "${VERSIONS_DIR}" push origin "${VERSIONS_BRANCH}" --quiet; then
    echo "Pushed Loophole ${RELEASE_VERSION} metadata to ${VERSIONS_REPOSITORY}"
    exit 0
  fi

  if [[ "${attempt}" -lt 3 ]]; then
    echo "Versions push attempt ${attempt} failed; rebasing and retrying" >&2
    git -C "${VERSIONS_DIR}" pull --rebase origin "${VERSIONS_BRANCH}"
  fi
done

echo "Failed to push versions metadata after three attempts" >&2
exit 1
