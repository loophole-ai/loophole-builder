#!/usr/bin/env bash

set -ex

cd cli

export CARGO_NET_GIT_FETCH_WITH_CLI="true"
VSCODE_CLI_APPLICATION_NAME=$(node -p "require('../product.json').applicationName")
VSCODE_CLI_BINARY_NAME=$(node -p "require('../product.json').serverApplicationName")
VSCODE_CLI_NAME_LONG=$(node -p "require('../product.json').nameLong")
VSCODE_CLI_DATA_FOLDER_NAME=$(node -p "require('../product.json').dataFolderName")
VSCODE_CLI_SERVER_DATA_FOLDER_NAME=$(node -p "require('../product.json').serverDataFolderName")
VSCODE_CLI_VERSION=${LOOPHOLE_VERSION:-$(node -p "require('../product.json').loopholeVersion")}
export VSCODE_CLI_APPLICATION_NAME VSCODE_CLI_BINARY_NAME VSCODE_CLI_NAME_LONG
export VSCODE_CLI_DATA_FOLDER_NAME VSCODE_CLI_SERVER_DATA_FOLDER_NAME VSCODE_CLI_VERSION
export VSCODE_CLI_QUALITYLESS_PRODUCT_NAME="Loophole"
export VSCODE_CLI_QUALITY="${VSCODE_QUALITY:-stable}"
export VSCODE_CLI_COMMIT="${MS_COMMIT:-}"
export VSCODE_CLI_DOCUMENTATION_URL="https://loophole.dev"
export VSCODE_CLI_TUNNEL_EDITOR_WEB_URL="https://loophole.dev"
export VSCODE_CLI_UPDATE_URL="https://raw.githubusercontent.com/loophole-ai/versions/refs/heads/main"

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  export VSCODE_CLI_DOWNLOAD_URL="https://github.com/loophole-ai/loophole-ide-insiders/releases"
else
  export VSCODE_CLI_DOWNLOAD_URL="https://github.com/loophole-ai/loophole-ide/releases"
fi

TUNNEL_APPLICATION_NAME="$( node -p "require(\"../product.json\").tunnelApplicationName" )"

npm pack @vscode/openssl-prebuilt@0.0.11
mkdir openssl
tar -xvzf vscode-openssl-prebuilt-0.0.11.tgz --strip-components=1 --directory=openssl
# Use the prebuilt archives above instead of invoking openssl-src (and Perl).
export OPENSSL_NO_VENDOR=1

if [[ "${OS_NAME}" == "osx" ]]; then
  if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
    VSCODE_CLI_TARGET="aarch64-apple-darwin"
  else
    VSCODE_CLI_TARGET="x86_64-apple-darwin"
  fi

  OPENSSL_LIB_DIR="$(pwd)/openssl/out/${VSCODE_ARCH}-osx/lib"
  OPENSSL_INCLUDE_DIR="$(pwd)/openssl/out/${VSCODE_ARCH}-osx/include"
  export OPENSSL_LIB_DIR OPENSSL_INCLUDE_DIR

  rustup target add "${VSCODE_CLI_TARGET}"
  export RUSTFLAGS="-A unused-imports"
  cargo build --release --target "${VSCODE_CLI_TARGET}" --bin=code

  cp "target/${VSCODE_CLI_TARGET}/release/code" "../../VSCode-darwin-${VSCODE_ARCH}/${VSCODE_CLI_NAME_LONG}.app/Contents/Resources/app/bin/${TUNNEL_APPLICATION_NAME}"
elif [[ "${OS_NAME}" == "windows" ]]; then
  # Git Bash places usr\bin very early in PATH: rustc then invokes Unix "link.exe",
  # not the MSVC linker (error "/usr/bin/link: extra operand").
  _sanitize_path_for_rust_windows() {
    local result="" dir norm tmp
    tmp="${PATH//;/:}"
    tmp="${tmp}:"
    while [[ -n "$tmp" ]]; do
      dir="${tmp%%:*}"
      tmp="${tmp#*:}"
      [[ -z "${dir}" ]] && continue
      norm="${dir//\\//}"
      if [[ "${norm}" =~ [Gg]it/.*/usr/bin ]]; then
        continue
      fi
      [[ -n "${result}" ]] && result="${result}:"
      result="${result}${dir}"
    done
    printf '%s' "${result}"
  }

  # VsDevCmd/msvc-dev-cmd must select the native MSVC linker for x64 or arm64.
  _force_msvc_linker_for_rust() {
    local host="${1}"
    local vc="${VCToolsInstallDir:-}"
    [[ -z "${vc}" ]] && return 0
    vc="${vc//\\//}"
    [[ "${vc}" != */ ]] && vc="${vc}/"
    local bindir="${vc}bin/Hostx64/${host}"
    local linkexe="${bindir}/link.exe"
    [[ ! -f "${linkexe}" ]] && return 0
    export PATH="${bindir}:${PATH}"
    case "${host}" in
      arm64) export CARGO_TARGET_AARCH64_PC_WINDOWS_MSVC_LINKER="${linkexe}" ;;
      x64) export CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER="${linkexe}" ;;
    esac
  }

  sanitized_path=$(_sanitize_path_for_rust_windows)
  export PATH="${sanitized_path}"

  if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
    VSCODE_CLI_TARGET="aarch64-pc-windows-msvc"
    _force_msvc_linker_for_rust "arm64"
    export VSCODE_CLI_RUST="-C target-feature=+crt-static -Clink-args=/guard:cf -Clink-args=/CETCOMPAT:NO"
  else
    VSCODE_CLI_TARGET="x86_64-pc-windows-msvc"
    _force_msvc_linker_for_rust "x64"
    export VSCODE_CLI_RUSTFLAGS="-Ctarget-feature=+crt-static -Clink-args=/guard:cf -Clink-args=/CETCOMPAT"
  fi

  export VSCODE_CLI_CFLAGS="/guard:cf /Qspectre"
  OPENSSL_LIB_DIR="$(pwd)/openssl/out/${VSCODE_ARCH}-windows-static/lib"
  OPENSSL_INCLUDE_DIR="$(pwd)/openssl/out/${VSCODE_ARCH}-windows-static/include"
  export OPENSSL_LIB_DIR OPENSSL_INCLUDE_DIR

  rustup target add "${VSCODE_CLI_TARGET}"

  export RUSTFLAGS="-A unused-imports"
  cargo build --release --target "${VSCODE_CLI_TARGET}" --bin=code

  cp "target/${VSCODE_CLI_TARGET}/release/code.exe" "../../VSCode-win32-${VSCODE_ARCH}/bin/${TUNNEL_APPLICATION_NAME}.exe"
else
  OPENSSL_LIB_DIR="$(pwd)/openssl/out/${VSCODE_ARCH}-linux/lib"
  OPENSSL_INCLUDE_DIR="$(pwd)/openssl/out/${VSCODE_ARCH}-linux/include"
  export OPENSSL_LIB_DIR OPENSSL_INCLUDE_DIR
  export VSCODE_SYSROOT_DIR="../.build/sysroots"

  if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
    VSCODE_CLI_TARGET="aarch64-unknown-linux-gnu"

    if [[ "${CI_BUILD}" != "no" ]]; then
      export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
      export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
      export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
      export PKG_CONFIG_ALLOW_CROSS=1
    fi
  elif [[ "${VSCODE_ARCH}" == "armhf" ]]; then
    VSCODE_CLI_TARGET="armv7-unknown-linux-gnueabihf"

    OPENSSL_LIB_DIR="$(pwd)/openssl/out/arm-linux/lib"
    OPENSSL_INCLUDE_DIR="$(pwd)/openssl/out/arm-linux/include"
    export OPENSSL_LIB_DIR OPENSSL_INCLUDE_DIR

    if [[ "${CI_BUILD}" != "no" ]]; then
      export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc
      export CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc
      export CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++
      export PKG_CONFIG_ALLOW_CROSS=1
    fi
  elif [[ "${VSCODE_ARCH}" == "x64" ]]; then
    VSCODE_CLI_TARGET="x86_64-unknown-linux-gnu"
  fi

  if [[ -n "${VSCODE_CLI_TARGET}" ]]; then
    rustup target add "${VSCODE_CLI_TARGET}"

    export RUSTFLAGS="-A unused-imports"
    cargo build --release --target "${VSCODE_CLI_TARGET}" --bin=code

    cp "target/${VSCODE_CLI_TARGET}/release/code" "../../VSCode-linux-${VSCODE_ARCH}/bin/${TUNNEL_APPLICATION_NAME}"
  fi
fi

cd ..
