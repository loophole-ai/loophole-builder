#!/usr/bin/env bash

set -ex

CALLER_DIR=$( pwd )

cd "$( dirname "${BASH_SOURCE[0]}" )"

if [[ "${VSCODE_ARCH}" == "x64" ]]; then
  GITHUB_RESPONSE=$( curl --silent --location "https://api.github.com/repos/AppImage/pkg2appimage/releases/latest" )
  APPIMAGE_URL=$( echo "${GITHUB_RESPONSE}" | jq --raw-output '.assets | map(select( .name | test("x86_64.AppImage(?!.zsync)"))) | map(.browser_download_url)[0]' )

  if [[ -z "${APPIMAGE_URL}" ]]; then
    echo "The url for pkg2appimage.AppImage hasn't been found"
    exit 1
  fi

  wget -c "${APPIMAGE_URL}" -O pkg2appimage.AppImage

  chmod +x ./pkg2appimage.AppImage

  ./pkg2appimage.AppImage --appimage-extract && mv ./squashfs-root ./pkg2appimage.AppDir

  # Add the Loophole GitHub release update information.
  sed -i 's/generate_type2_appimage/generate_type2_appimage -u "gh-releases-zsync|loophole-ai|loophole-ide|latest|*.AppImage.zsync"/' pkg2appimage.AppDir/AppRun

  # remove check so build in docker can succeed
  sed -i 's/grep docker/# grep docker/' pkg2appimage.AppDir/usr/share/pkg2appimage/functions.sh

  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    sed -i 's|@@NAME@@|Loophole-Insiders|g' recipe.yml
    sed -i 's|@@APPNAME@@|loophole-insiders|g' recipe.yml
    sed -i 's|@@ICON@@|loophole-insiders|g' recipe.yml
  else
    sed -i 's|@@NAME@@|Loophole|g' recipe.yml
    sed -i 's|@@APPNAME@@|loophole|g' recipe.yml
    sed -i 's|@@ICON@@|loophole|g' recipe.yml
  fi

  # pkg2appimage must run as x86_64 on hosted x64 runners.
  export ARCH=x86_64
  bash -ex pkg2appimage.AppDir/AppRun recipe.yml

  rm -f pkg2appimage-*.AppImage
  rm -rf pkg2appimage.AppDir
  rm -rf Loophole*
fi

cd "${CALLER_DIR}"
