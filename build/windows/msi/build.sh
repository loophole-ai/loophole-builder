#!/usr/bin/env bash

set -ex

CALLER_DIR=$(pwd)
cd "$(dirname "${BASH_SOURCE[0]}")"

WIN_SDK_MAJOR_VERSION="10"
WIN_SDK_FULL_VERSION="10.0.17763.0"

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  PRODUCT_NAME="Loophole - Insiders"
  PRODUCT_CODE="LoopholeInsiders"
  PRODUCT_UPGRADE_CODE="1C9B7195-5A9A-43B3-B4BD-583E20498467"
  ICON_DIR="..\\..\\..\\vscode\\resources\\win32"
  SETUP_RESOURCES_DIR=".\\resources\\insider"
else
  PRODUCT_NAME="Loophole"
  PRODUCT_CODE="Loophole"
  PRODUCT_UPGRADE_CODE="965370CD-253C-4720-82FC-2E6B02A53808"
  ICON_DIR="..\\..\\..\\vscode\\resources\\win32"
  SETUP_RESOURCES_DIR=".\\resources\\stable"
fi

PRODUCT_ID=$(powershell.exe -command "[guid]::NewGuid().ToString().ToUpper()")
PRODUCT_ID="${PRODUCT_ID%%[[:cntrl:]]}"

CULTURE="en-us"
LANGID="1033"
SETUP_RELEASE_DIR=".\\releasedir"
BINARY_DIR="..\\..\\..\\VSCode-win32-${VSCODE_ARCH}"
LICENSE_DIR="..\\..\\..\\vscode"
PROGRAM_FILES_86=$(env | sed -n 's/^ProgramFiles(x86)=//p')
APP_NAME="${APP_NAME:-Loophole}"

# WiX accepts only a numeric x.y.z.w product version. Use the VS Code base version.
PRODUCT_VERSION_WIX="${RELEASE_VERSION%-insider}"
PRODUCT_VERSION_WIX="${PRODUCT_VERSION_WIX%%-*}"

if [[ -z "${1}" ]]; then
  OUTPUT_BASE_FILENAME="${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}"
else
  OUTPUT_BASE_FILENAME="${APP_NAME}-${VSCODE_ARCH}-${1}-${RELEASE_VERSION}"
fi

if [[ "${VSCODE_ARCH}" == "ia32" ]]; then
  export PLATFORM="x86"
else
  export PLATFORM="${VSCODE_ARCH}"
fi

sed -i "s|@@PRODUCT_UPGRADE_CODE@@|${PRODUCT_UPGRADE_CODE}|g" .\\includes\\loophole-variables.wxi
sed -i "s|@@PRODUCT_NAME@@|${PRODUCT_NAME}|g" .\\loophole.xsl
sed -i "s|@@PRODUCT_NAME@@|${PRODUCT_NAME}|g" .\\i18n\\loophole.en-us.wxl

"${WIX}bin\\heat.exe" dir "${BINARY_DIR}" \
  -out "Files-${OUTPUT_BASE_FILENAME}.wxs" \
  -t loophole.xsl \
  -gg -sfrag -scom -sreg -srd -ke \
  -cg "AppFiles" \
  -var var.ManufacturerName \
  -var var.AppName \
  -var var.AppCodeName \
  -var var.ProductVersion \
  -var var.IconDir \
  -var var.LicenseDir \
  -var var.BinaryDir \
  -dr APPLICATIONFOLDER \
  -platform "${PLATFORM}"

"${WIX}bin\\candle.exe" -arch "${PLATFORM}" \
  loophole.wxs "Files-${OUTPUT_BASE_FILENAME}.wxs" \
  -ext WixUIExtension -ext WixUtilExtension -ext WixNetFxExtension \
  -dManufacturerName="Loophole AI" \
  -dAppCodeName="${PRODUCT_CODE}" \
  -dAppName="${PRODUCT_NAME}" \
  -dProductVersion="${PRODUCT_VERSION_WIX}" \
  -dProductId="${PRODUCT_ID}" \
  -dBinaryDir="${BINARY_DIR}" \
  -dIconDir="${ICON_DIR}" \
  -dLicenseDir="${LICENSE_DIR}" \
  -dSetupResourcesDir="${SETUP_RESOURCES_DIR}" \
  -dCulture="${CULTURE}"

"${WIX}bin\\light.exe" loophole.wixobj "Files-${OUTPUT_BASE_FILENAME}.wixobj" \
  -ext WixUIExtension -ext WixUtilExtension -ext WixNetFxExtension \
  -spdb \
  -cc "${TEMP}\\loophole-cab-cache\\${PLATFORM}" \
  -out "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi" \
  -loc "i18n\\loophole.en-us.wxl" \
  -cultures:"${CULTURE}" \
  -sice:ICE60 -sice:ICE69

# Mark the installer package as English (United States).
cscript "${PROGRAM_FILES_86}\\Windows Kits\\${WIN_SDK_MAJOR_VERSION}\\bin\\${WIN_SDK_FULL_VERSION}\\${PLATFORM}\\WiLangId.vbs" \
  "${SETUP_RELEASE_DIR}\\${OUTPUT_BASE_FILENAME}.msi" Package "${LANGID}"

rm -rf "${TEMP}\\loophole-cab-cache"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wxs"
rm -f "Files-${OUTPUT_BASE_FILENAME}.wixobj"
rm -f "loophole.wixobj"

cd "${CALLER_DIR}"
