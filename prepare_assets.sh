#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

# Linux CI currently publishes tar.gz archives only. DEB, RPM, and AppImage packaging
# require additional system dependencies that are disabled in the hosted workflow.
if [[ "${OS_NAME}" == "linux" && "${GITHUB_ACTIONS}" == "true" ]]; then
  [[ "${SHOULD_BUILD_DEB}" == "yes" ]] || SHOULD_BUILD_DEB="no"
  [[ "${SHOULD_BUILD_RPM}" == "yes" ]] || SHOULD_BUILD_RPM="no"
  [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" ]] || SHOULD_BUILD_APPIMAGE="no"
  echo "Linux CI: DEB=${SHOULD_BUILD_DEB} RPM=${SHOULD_BUILD_RPM} APPIMAGE=${SHOULD_BUILD_APPIMAGE} TAR=${SHOULD_BUILD_TAR:-yes}"
fi

# Use the version selected by the check job. Fall back to source metadata for local builds.
loopholeVersion="${LOOPHOLE_VERSION:-${RELEASE_VERSION:-}}"
[[ "${loopholeVersion}" == "null" ]] && loopholeVersion=""
if [[ -z "${loopholeVersion}" && -f vscode/product.json ]]; then
  loopholeVersion=$(jq -r '.loopholeVersion // empty' vscode/product.json)
  [[ "${loopholeVersion}" == "null" ]] && loopholeVersion=""
fi
if [[ -z "${loopholeVersion}" ]]; then
  echo "Loophole version is not set" >&2
  exit 1
fi

APP_NAME="${APP_NAME:-Loophole}"

# Support both the current and legacy macOS secret names.
CERTIFICATE_OSX_APP_PASSWORD="${CERTIFICATE_OSX_NEW_APP_PASSWORD:-${CERTIFICATE_OSX_APP_PASSWORD}}"
CERTIFICATE_OSX_ID="${CERTIFICATE_OSX_NEW_ID:-${CERTIFICATE_OSX_ID}}"
CERTIFICATE_OSX_P12_DATA="${CERTIFICATE_OSX_NEW_P12_DATA:-${CERTIFICATE_OSX_P12_DATA}}"
CERTIFICATE_OSX_P12_PASSWORD="${CERTIFICATE_OSX_NEW_P12_PASSWORD:-${CERTIFICATE_OSX_P12_PASSWORD}}"
CERTIFICATE_OSX_TEAM_ID="${CERTIFICATE_OSX_NEW_TEAM_ID:-${CERTIFICATE_OSX_TEAM_ID}}"

APP_NAME_LC="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"

mkdir -p assets

if [[ "${OS_NAME}" == "osx" ]]; then
  if [[ "${SHOULD_DEPLOY:-no}" == "yes" && -n "${CERTIFICATE_OSX_P12_DATA}" ]]; then
    if [[ "${CI_BUILD}" == "no" ]]; then
      RUNNER_TEMP="${TMPDIR}"
    fi

    CERTIFICATE_P12="${APP_NAME}.p12"
    KEYCHAIN="${RUNNER_TEMP}/buildagent.keychain"
    AGENT_TEMPDIRECTORY="${RUNNER_TEMP}"
    # shellcheck disable=SC2006
    KEYCHAINS=`security list-keychains | xargs`

    rm -f "${KEYCHAIN}"

    echo "${CERTIFICATE_OSX_P12_DATA}" | base64 --decode > "${CERTIFICATE_P12}"

    echo "+ create temporary keychain"
    security create-keychain -p pwd "${KEYCHAIN}"
    security set-keychain-settings -lut 21600 "${KEYCHAIN}"
    security unlock-keychain -p pwd "${KEYCHAIN}"
    # shellcheck disable=SC2086
    security list-keychains -s $KEYCHAINS "${KEYCHAIN}"
    # security show-keychain-info "${KEYCHAIN}"

    echo "+ import certificate to keychain"
    security import "${CERTIFICATE_P12}" -k "${KEYCHAIN}" -P "${CERTIFICATE_OSX_P12_PASSWORD}" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k pwd "${KEYCHAIN}" > /dev/null
    # security find-identity "${KEYCHAIN}"

    CODESIGN_IDENTITY="$( security find-identity -v -p codesigning "${KEYCHAIN}" | grep -oEi "([0-9A-F]{40})" | head -n 1 )"

    echo "+ signing"
    export CODESIGN_IDENTITY AGENT_TEMPDIRECTORY

    DEBUG="electron-osx-sign*" node --experimental-strip-types vscode/build/darwin/sign.ts "$( pwd )"
    # codesign --display --entitlements :- ""

    echo "+ notarize"

    cd "VSCode-darwin-${VSCODE_ARCH}"
    ZIP_FILE="./${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.zip"

    zip -r -X -y "${ZIP_FILE}" ./*.app

    xcrun notarytool store-credentials "${APP_NAME}" --apple-id "${CERTIFICATE_OSX_ID}" --team-id "${CERTIFICATE_OSX_TEAM_ID}" --password "${CERTIFICATE_OSX_APP_PASSWORD}" --keychain "${KEYCHAIN}"
    # xcrun notarytool history --keychain-profile "${APP_NAME}" --keychain "${KEYCHAIN}"
    xcrun notarytool submit "${ZIP_FILE}" --keychain-profile "${APP_NAME}" --wait --keychain "${KEYCHAIN}"

    echo "+ attach staple"
    xcrun stapler staple ./*.app
    # spctl --assess -vv --type install ./*.app

    rm "${ZIP_FILE}"

    cd ..
  fi

  if [[ "${SHOULD_BUILD_ZIP}" != "no" ]]; then
    echo "Building and moving ZIP"
    cd "VSCode-darwin-${VSCODE_ARCH}"
    zip -r -X -y "../assets/${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.zip" ./*.app
    cd ..
  fi

  if [[ "${SHOULD_BUILD_DMG}" != "no" ]]; then
    echo "Building and moving DMG"
    # Install create-dmg outside the packaged application directory so npm can resolve it.
    CREATE_DMG_PREFIX="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/loophole-create-dmg"
    CREATE_DMG_BIN="${CREATE_DMG_PREFIX}/node_modules/.bin/create-dmg"
    mkdir -p "${CREATE_DMG_PREFIX}"
    if [[ ! -x "${CREATE_DMG_BIN}" ]]; then
      npm install --prefix="${CREATE_DMG_PREFIX}" --no-save create-dmg@8.1.0
    fi
    if [[ ! -x "${CREATE_DMG_BIN}" ]]; then
      echo "create-dmg not found after install (expected: ${CREATE_DMG_BIN})" >&2
      exit 1
    fi
    pushd "VSCode-darwin-${VSCODE_ARCH}"
    create_dmg_flags=(--overwrite)
    if [[ "${SHOULD_DEPLOY:-no}" != "yes" ]]; then
      create_dmg_flags+=(--no-code-sign)
    fi

    # appdmg can race with macOS unmounting the temporary volume. Retry that
    # known cleanup race, and overwrite any partial target left by the attempt.
    create_dmg_attempt=1
    create_dmg_max_attempts=3
    create_dmg_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/loophole-create-dmg-${VSCODE_ARCH}.log"
    while true; do
      if "${CREATE_DMG_BIN}" "${create_dmg_flags[@]}" ./*.app . >"${create_dmg_log}" 2>&1; then
        cat "${create_dmg_log}"
        break
      fi

      cat "${create_dmg_log}" >&2
      if [[ "${create_dmg_attempt}" -ge "${create_dmg_max_attempts}" ]] ||
        ! grep -qF "hdiutil: detach failed" "${create_dmg_log}"; then
        exit 1
      fi

      echo "DMG cleanup did not find the temporary volume; retrying (${create_dmg_attempt}/${create_dmg_max_attempts})"
      sleep $((create_dmg_attempt * 2))
      create_dmg_attempt=$((create_dmg_attempt + 1))
    done
    # Keep the release asset name aligned with the IDE updater and versions feed.
    shopt -s nullglob
    dmg_files=( *.dmg )
    shopt -u nullglob
    if [[ "${#dmg_files[@]}" -ne 1 ]]; then
      echo "Expected exactly one generated DMG, found ${#dmg_files[@]}" >&2
      exit 1
    fi
    mv "${dmg_files[0]}" "../assets/${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.dmg"
    popd
  fi

  if [[ "${SHOULD_BUILD_SRC}" == "yes" ]]; then
    git archive --format tar.gz --output="./assets/${APP_NAME}-${RELEASE_VERSION}-src.tar.gz" HEAD
    git archive --format zip --output="./assets/${APP_NAME}-${RELEASE_VERSION}-src.zip" HEAD
  fi

  if [[ "${SHOULD_DEPLOY:-no}" == "yes" && -n "${CERTIFICATE_OSX_P12_DATA}" ]]; then
    echo "+ clean"
    security delete-keychain "${KEYCHAIN}"
    # shellcheck disable=SC2086
    security list-keychains -s $KEYCHAINS
  fi

  VSCODE_PLATFORM="darwin"
elif [[ "${OS_NAME}" == "windows" ]]; then
  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  # Loophole does not publish the Appx/MSIX context-menu package.
  if [[ -f build/gulpfile.vscode.win32.ts ]]; then
    node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync} = require('fs');
const f = 'build/gulpfile.vscode.win32.ts';
let c = readFileSync(f, 'utf8');
const needle = "if (quality === 'stable' || quality === 'insider') {";
const patch = "if (false /* Loophole: no Appx package */ && (quality === 'stable' || quality === 'insider')) {";
if (c.includes(needle) && !c.includes('Loophole: no Appx package')) {
  c = c.replace(needle, patch);
  writeFileSync(f, c);
  console.log('patched build/gulpfile.vscode.win32.ts: Appx disabled');
}
NODEEOF
  fi

  # Inno Setup requires a four-part package version. Patch it temporarily, then restore the base version.
  # shellcheck source=scripts/lib/ci_lib.sh
  source "${LOOPHOLE_BUILDER_ROOT:-${GITHUB_WORKSPACE:-.}}/scripts/lib/ci_lib.sh"
  ci_apply_win_inno_package_version

  npm run gulp "vscode-win32-${VSCODE_ARCH}-inno-updater"

  if [[ "${SHOULD_BUILD_ZIP}" != "no" ]]; then
    7z.exe a -tzip "../assets/${APP_NAME}-win32-${VSCODE_ARCH}-${RELEASE_VERSION}.zip" -x!CodeSignSummary*.md -x!tools "../VSCode-win32-${VSCODE_ARCH}/*" -r
  fi

  if [[ "${SHOULD_BUILD_EXE_SYS}" != "no" ]]; then
    npm run gulp "vscode-win32-${VSCODE_ARCH}-system-setup"
  fi

  if [[ "${SHOULD_BUILD_EXE_USR}" != "no" ]]; then
    npm run gulp "vscode-win32-${VSCODE_ARCH}-user-setup"
  fi

  ci_restore_package_json_version

  if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]]; then
    if [[ "${SHOULD_BUILD_MSI}" != "no" ]]; then
      . ../build/windows/msi/build.sh
    fi

    if [[ "${SHOULD_BUILD_MSI_NOUP}" != "no" ]]; then
      . ../build/windows/msi/build-updates-disabled.sh
    fi
  fi

  cd ..

  if [[ "${SHOULD_BUILD_EXE_SYS}" != "no" ]]; then
    echo "Moving System EXE"
    mv "vscode\\.build\\win32-${VSCODE_ARCH}\\system-setup\\VSCodeSetup.exe" "assets\\${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  fi

  if [[ "${SHOULD_BUILD_EXE_USR}" != "no" ]]; then
    echo "Moving User EXE"
    mv "vscode\\.build\\win32-${VSCODE_ARCH}\\user-setup\\VSCodeSetup.exe" "assets\\${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  fi

  if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]]; then
    if [[ "${SHOULD_BUILD_MSI}" != "no" ]]; then
      echo "Moving MSI"
      mv "build\\windows\\msi\\releasedir\\${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}.msi" assets/
    fi

    if [[ "${SHOULD_BUILD_MSI_NOUP}" != "no" ]]; then
      echo "Moving MSI with disabled updates"
      mv "build\\windows\\msi\\releasedir\\${APP_NAME}-${VSCODE_ARCH}-updates-disabled-${RELEASE_VERSION}.msi" assets/
    fi
  fi

  VSCODE_PLATFORM="win32"
else
  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  if [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" && "${VSCODE_ARCH}" != "x64" ]]; then
    SHOULD_BUILD_APPIMAGE="no"
  fi

  if [[ "${SHOULD_BUILD_DEB}" == "yes" ]]; then
    npm run gulp "vscode-linux-${VSCODE_ARCH}-prepare-deb"
    npm run gulp "vscode-linux-${VSCODE_ARCH}-build-deb"
  fi

  if [[ "${SHOULD_BUILD_RPM}" == "yes" ]]; then
    npm run gulp "vscode-linux-${VSCODE_ARCH}-prepare-rpm"
    npm run gulp "vscode-linux-${VSCODE_ARCH}-build-rpm"
  fi

  if [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" ]]; then
    . ../build/linux/appimage/build.sh
  fi

  cd ..

  if [[ "${CI_BUILD}" == "no" && "${SKIP_ASSETS}" == "no" ]]; then
    echo "Snap packages are built separately from stores/snapcraft/{stable,insider}."
  fi

  if [[ "${SHOULD_BUILD_TAR}" != "no" ]]; then
    echo "Building and moving TAR"
    cd "VSCode-linux-${VSCODE_ARCH}"
    tar czf "../assets/${APP_NAME}-linux-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .
    cd ..
  fi

  if [[ "${SHOULD_BUILD_DEB}" == "yes" ]]; then
    echo "Moving DEB"
    mv vscode/.build/linux/deb/*/deb/*.deb assets/
  fi

  if [[ "${SHOULD_BUILD_RPM}" == "yes" ]]; then
    echo "Moving RPM"
    mv vscode/.build/linux/rpm/*/*.rpm assets/
  fi

  if [[ "${SHOULD_BUILD_APPIMAGE}" == "yes" ]]; then
    echo "Moving AppImage"
    mv build/linux/appimage/out/*.AppImage* assets/

    find assets -name '*.AppImage*' -exec bash -c 'mv $0 ${0/_-_/-}' {} \;
  fi

  VSCODE_PLATFORM="linux"
fi

if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
  echo "Building and moving REH"
  cd "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}"
  tar czf "../assets/${APP_NAME_LC}-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .
  cd ..
fi

if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
  echo "Building and moving REH-web"
  cd "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}"
  tar czf "../assets/${APP_NAME_LC}-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .
  cd ..
fi

write_asset_checksums() {
  local file="${1}"
  if [[ ! -f "${file}" ]]; then
    return 0
  fi
  echo "Calculating checksum for ${file}"
  if [[ "${OS_NAME}" == "osx" ]] && command -v shasum &>/dev/null; then
    shasum -a 256 "${file}" | awk '{print $1}' > "${file}.sha256"
  elif command -v checksum &>/dev/null; then
    checksum -a sha256 "${file}" > "${file}.sha256"
  elif [[ "${OS_NAME}" == "windows" ]] && command -v certutil &>/dev/null; then
    certutil -hashfile "${file}" SHA256 | awk 'NR==2 {print $1}' > "${file}.sha256"
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "${file}" | awk '{print $1}' > "${file}.sha256"
  elif command -v sha256sum &>/dev/null; then
    sha256sum "${file}" | awk '{print $1}' > "${file}.sha256"
  else
    echo "No checksum tool available for ${file}" >&2
    return 1
  fi
}

(
  cd assets
  for FILE in *; do
    if [[ -f "${FILE}" && "${FILE}" != *.sha1 && "${FILE}" != *.sha256 ]]; then
      write_asset_checksums "${FILE}"
    fi
  done
)
