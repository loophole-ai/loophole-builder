#!/usr/bin/env bash

set -ex

sudo apt-get update -y

# Native module build headers (native-keymap, keytar, kerberos, etc.)
sudo apt-get install -y \
  pkg-config \
  libkrb5-dev \
  libx11-dev \
  libxkbfile-dev \
  libsecret-1-dev \
  libxtst-dev

if [[ "${VSCODE_ARCH}" == "arm64" ]]; then
  sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu crossbuild-essential-arm64
elif [[ "${VSCODE_ARCH}" == "armhf" ]]; then
  sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf crossbuild-essential-armhf
fi
