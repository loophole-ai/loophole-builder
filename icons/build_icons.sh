#!/usr/bin/env bash
# Generate Loophole application and file icons directly in the checked-out IDE source tree.

set -e

BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VSCODE_DIR="${VSCODE_DIR:-${BUILDER_ROOT}/vscode}"
VSCODE_QUALITY="${VSCODE_QUALITY:-stable}"

case "${VSCODE_QUALITY}" in
  stable|insider) ;;
  *)
    echo "Unsupported VSCODE_QUALITY: ${VSCODE_QUALITY}" >&2
    exit 1
    ;;
esac

if [[ ! -d "${VSCODE_DIR}" ]]; then
  echo "IDE source directory not found: ${VSCODE_DIR}" >&2
  exit 1
fi

require_program() {
  if ! command -v "$1" &>/dev/null; then
    echo "Required program not found: $1" >&2
    exit 1
  fi
}

require_program convert
require_program base64

LOGO="${BUILDER_ROOT}/icons/${VSCODE_QUALITY}/loophole_logo.png"
ONBOARDING_LOGO="${BUILDER_ROOT}/icons/${VSCODE_QUALITY}/onboarding_logo180.png"
MACOS_TEMPLATE="${BUILDER_ROOT}/icons/template_macos.png"

for asset in "${LOGO}" "${ONBOARDING_LOGO}" "${MACOS_TEMPLATE}"; do
  if [[ ! -f "${asset}" ]]; then
    echo "Loophole icon asset not found: ${asset}" >&2
    exit 1
  fi
done

build_darwin_icons() {
  local darwin_dir="${VSCODE_DIR}/resources/darwin"
  local source_dir="${VSCODE_DIR}/resources/darwin"
  local tmp_16 tmp_32 tmp_64 tmp_128 tmp_256 tmp_512 tmp_1024 iconset file name

  mkdir -p "${darwin_dir}"
  tmp_16="${darwin_dir}/.loophole-16.png"
  tmp_32="${darwin_dir}/.loophole-32.png"
  tmp_64="${darwin_dir}/.loophole-64.png"
  tmp_128="${darwin_dir}/.loophole-128.png"
  tmp_256="${darwin_dir}/.loophole-256.png"
  tmp_512="${darwin_dir}/.loophole-512.png"
  tmp_1024="${darwin_dir}/.loophole-1024.png"

  convert "${MACOS_TEMPLATE}" -filter Lanczos -resize 1024x1024 "${tmp_1024}"
  convert "${tmp_1024}" -filter Lanczos -resize 16x16 "${tmp_16}"
  convert "${tmp_1024}" -filter Lanczos -resize 32x32 "${tmp_32}"
  convert "${tmp_1024}" -filter Lanczos -resize 64x64 "${tmp_64}"
  convert "${tmp_1024}" -filter Lanczos -resize 128x128 "${tmp_128}"
  convert "${tmp_1024}" -filter Lanczos -resize 256x256 "${tmp_256}"
  convert "${tmp_1024}" -filter Lanczos -resize 512x512 "${tmp_512}"

  rm -f "${darwin_dir}/code.icns"
  if command -v png2icns >/dev/null 2>&1; then
    png2icns "${darwin_dir}/code.icns" "${tmp_512}" "${tmp_256}" "${tmp_128}"
  elif command -v iconutil >/dev/null 2>&1; then
    # macOS does not provide png2icns through Homebrew. Use the native
    # iconutil command with the standard macOS iconset layout instead.
    iconset="${darwin_dir}/.loophole.iconset"
    rm -rf "${iconset}"
    mkdir -p "${iconset}"
    cp "${tmp_16}" "${iconset}/icon_16x16.png"
    cp "${tmp_32}" "${iconset}/icon_16x16@2x.png"
    cp "${tmp_32}" "${iconset}/icon_32x32.png"
    cp "${tmp_64}" "${iconset}/icon_32x32@2x.png"
    cp "${tmp_128}" "${iconset}/icon_128x128.png"
    cp "${tmp_256}" "${iconset}/icon_128x128@2x.png"
    cp "${tmp_256}" "${iconset}/icon_256x256.png"
    cp "${tmp_512}" "${iconset}/icon_256x256@2x.png"
    cp "${tmp_512}" "${iconset}/icon_512x512.png"
    cp "${tmp_1024}" "${iconset}/icon_512x512@2x.png"
    if ! iconutil -c icns "${iconset}" -o "${darwin_dir}/code.icns"; then
      rm -rf "${iconset}"
      echo "Failed to create macOS icon with iconutil" >&2
      return 1
    fi
    rm -rf "${iconset}"
  else
    echo "Required program not found: png2icns or iconutil" >&2
    return 1
  fi

  # Language/file icons otherwise shipped by the IDE still use upstream branding.
  for file in "${source_dir}"/*.icns; do
    [[ -f "${file}" ]] || continue
    name=$(basename "${file}")
    [[ "${name}" == "code.icns" ]] && continue
    cp "${darwin_dir}/code.icns" "${file}"
  done

  rm -f "${tmp_16}" "${tmp_32}" "${tmp_64}" "${tmp_128}" "${tmp_256}" "${tmp_512}" "${tmp_1024}"
}

build_linux_icons() {
  local linux_dir="${VSCODE_DIR}/resources/linux"

  mkdir -p "${linux_dir}/rpm"
  convert "${LOGO}" -filter Lanczos -resize 512x512 "${linux_dir}/code.png"
  convert "${linux_dir}/code.png" "${linux_dir}/rpm/code.xpm"
}

write_embedded_logo_svg() {
  local output="$1"
  local width="$2"
  local height="$3"
  local logo_data

  logo_data=$(base64 < "${LOGO}" | tr -d '\r\n')
  mkdir -p "$(dirname "${output}")"
  cat > "${output}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <image href="data:image/png;base64,${logo_data}" width="${width}" height="${height}" />
</svg>
EOF
}

build_windows_icon_set() {
  local output="$1"
  local logo_size="$2"
  local background="$3"

  if [[ "${output}" == *.ico ]]; then
    convert "${LOGO}" -background none -define icon:auto-resize=256,128,96,64,48,32,24,16 "${output}"
  elif [[ "${output}" == *.png ]]; then
    convert -size "${background}" "xc:transparent" \( "${LOGO}" -filter Lanczos -resize "${logo_size}x${logo_size}" \) -gravity center -composite "${output}"
  else
    convert -size "${background}" xc:white \( "${LOGO}" -filter Lanczos -resize "${logo_size}x${logo_size}" \) -gravity center -composite "${output}"
  fi
}

build_windows_icons() {
  local win32_dir="${VSCODE_DIR}/resources/win32"
  local source_dir="${VSCODE_DIR}/resources/win32"
  local file name

  mkdir -p "${win32_dir}"
  build_windows_icon_set "${win32_dir}/code.ico" 256 transparent

  # Replace upstream file and language icons with Loophole-branded icons.
  for file in "${source_dir}"/*.ico; do
    [[ -f "${file}" ]] || continue
    name=$(basename "${file}")
    [[ "${name}" == "code.ico" ]] && continue
    build_windows_icon_set "${file}" 256 transparent
  done

  build_windows_icon_set "${win32_dir}/code_70x70.png" 45 transparent
  build_windows_icon_set "${win32_dir}/code_150x150.png" 120 transparent

  build_windows_icon_set "${win32_dir}/inno-big-100.bmp" 110 xc:white
  build_windows_icon_set "${win32_dir}/inno-big-125.bmp" 128 xc:white
  build_windows_icon_set "${win32_dir}/inno-big-150.bmp" 165 xc:white
  build_windows_icon_set "${win32_dir}/inno-big-175.bmp" 184 xc:white
  build_windows_icon_set "${win32_dir}/inno-big-200.bmp" 220 xc:white
  build_windows_icon_set "${win32_dir}/inno-big-225.bmp" 238 xc:white
  build_windows_icon_set "${win32_dir}/inno-big-250.bmp" 275 xc:white
  build_windows_icon_set "${win32_dir}/inno-small-100.bmp" 38 xc:white
  build_windows_icon_set "${win32_dir}/inno-small-125.bmp" 44 xc:white
  build_windows_icon_set "${win32_dir}/inno-small-150.bmp" 56 xc:white
  build_windows_icon_set "${win32_dir}/inno-small-175.bmp" 62 xc:white
  build_windows_icon_set "${win32_dir}/inno-small-200.bmp" 74 xc:white
  build_windows_icon_set "${win32_dir}/inno-small-225.bmp" 80 xc:white
  build_windows_icon_set "${win32_dir}/inno-small-250.bmp" 92 xc:white
}

build_server_icons() {
  local server_dir="${VSCODE_DIR}/resources/server"

  mkdir -p "${server_dir}"
  convert "${LOGO}" -background none -define icon:auto-resize=256,128,64,48,32,16 "${server_dir}/favicon.ico"
  convert "${LOGO}" -filter Lanczos -resize 192x192 "${server_dir}/code-192.png"
  convert "${LOGO}" -filter Lanczos -resize 512x512 "${server_dir}/code-512.png"
}

build_workbench_icons() {
  local media_dir="${VSCODE_DIR}/src/vs/workbench/browser/media"
  local editor_media_dir="${VSCODE_DIR}/src/vs/workbench/browser/parts/editor/media"
  local brand_dir="${VSCODE_DIR}/resources/loophole"

  mkdir -p "${media_dir}" "${editor_media_dir}" "${brand_dir}"
  write_embedded_logo_svg "${media_dir}/code-icon.svg" 180 180
  cp "${ONBOARDING_LOGO}" "${editor_media_dir}/onboarding_logo180.png"
  cp "${BUILDER_ROOT}/icons/${VSCODE_QUALITY}/loophole_banner_dark.png" "${brand_dir}/loophole_banner_dark.png"
  cp "${BUILDER_ROOT}/icons/${VSCODE_QUALITY}/loophole_banner_light.png" "${brand_dir}/loophole_banner_light.png"

  # Replace the upstream letterpress artwork with the Loophole mark.
  local theme
  for theme in dark light hcDark hcLight; do
    write_embedded_logo_svg "${editor_media_dir}/letterpress-${theme}.svg" 180 180
  done
}

build_darwin_icons
build_linux_icons
build_windows_icons
build_server_icons
build_workbench_icons

echo "Generated Loophole ${VSCODE_QUALITY} icons in ${VSCODE_DIR}"
