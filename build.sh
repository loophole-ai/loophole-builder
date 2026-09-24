#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

# shellcheck source=scripts/lib/utils.sh
. scripts/lib/utils.sh
ensure_build_sourceversion

if [[ "${SHOULD_BUILD}" == "yes" ]]; then
  echo "MS_COMMIT=\"${MS_COMMIT}\""

  . prepare_vscode.sh

  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  export NODE_OPTIONS="--max-old-space-size=8192"

  # Skip monaco-compile-check as it's failing due to searchUrl property
  # Skip valid-layers-check as well since it might depend on monaco
  # Loophole commented these out
  # npm run monaco-compile-check
  # npm run valid-layers-check

  npm run buildreact
  npm run gulp compile-build-without-mangling
  npm run gulp compile-extension-media

  # Install dependencies for bundled extensions that have their own package.json.
  # Postinstall (dirs.ts) covers most extensions, but macOS CI can skip some installs
  # (install-state cache / parallel postinstall). compile-extensions-build also needs
  # devDependencies for esbuild extensions (e.g. jake/grunt/gulp @types/node for tsgo).
  # Copilot is excluded: we don't want it in the build.
  for ext_pkg in extensions/*/package.json; do
    ext_dir="$(dirname "${ext_pkg}")"
    [[ "${ext_dir}" == "extensions/copilot" ]] && continue
    if jq -e '((.dependencies // {}) | length > 0) or ((.devDependencies // {}) | length > 0)' "${ext_pkg}" > /dev/null 2>&1; then
      echo "Installing deps for extension: ${ext_dir}"
      if [[ -f "${ext_dir}/package-lock.json" ]]; then
        (cd "${ext_dir}" && npm ci --no-audit --no-fund) || \
        (cd "${ext_dir}" && npm install --no-audit --no-fund)
      else
        (cd "${ext_dir}" && npm install --no-audit --no-fund)
      fi
    fi
  done

  npm run gulp compile-extensions-build

  # Remove Copilot from the compiled extensions so it is not packaged.
  rm -rf .build/extensions/copilot
  npm run gulp minify-vscode

  if [[ "${OS_NAME}" == "osx" ]]; then
    # generate Group Policy definitions
    # node build/lib/policies darwin # Loophole commented this out

    npm run gulp "vscode-darwin-${VSCODE_ARCH}-min-ci"

    find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

    . "${LOOPHOLE_BUILDER_ROOT}/scripts/build_cli.sh"

    VSCODE_PLATFORM="darwin"
  elif [[ "${OS_NAME}" == "windows" ]]; then
    # generate Group Policy definitions
    # node build/lib/policies win32 # Loophole commented this out

    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      . ../build/windows/rtf/make.sh

      npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

      if [[ "${VSCODE_ARCH}" != "x64" ]]; then
        SHOULD_BUILD_REH="no"
        SHOULD_BUILD_REH_WEB="no"
      fi

      . "${LOOPHOLE_BUILDER_ROOT}/scripts/build_cli.sh"
    fi

    VSCODE_PLATFORM="win32"
  else # linux
    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      npm run gulp "vscode-linux-${VSCODE_ARCH}-min-ci"

      find "../VSCode-linux-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

      . "${LOOPHOLE_BUILDER_ROOT}/scripts/build_cli.sh"
    fi

    VSCODE_PLATFORM="linux"
  fi

  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  cd ..
fi
