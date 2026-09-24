#!/usr/bin/env bash
# shellcheck disable=SC1091,2154

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LOOPHOLE_BUILDER_ROOT="${REPO_ROOT}"
# shellcheck source=scripts/lib/utils.sh
. "${REPO_ROOT}/scripts/lib/utils.sh"
# shellcheck source=scripts/lib/ci_lib.sh
source "${REPO_ROOT}/scripts/lib/ci_lib.sh"

cd vscode || { echo "'vscode' directory not found"; exit 1; }

# Generate the Loophole platform icons directly in the IDE source tree.
"${REPO_ROOT}/icons/build_icons.sh"

# nls.ts uses `!typescript` which is falsy for empty strings "".
# An empty .ts file can produce sourcesContent:[""]
# which causes a spurious build error. Allow empty source content through; the patch()
# function already returns early when there are no localize() calls.
if [[ -f build/lib/nls.ts ]]; then
  replace 's/if \(!typescript\) \{/if (typescript == null) {/' build/lib/nls.ts
fi

"${REPO_ROOT}/scripts/update_settings.sh"

# Apply repository patches.
{ set +x; } 2>/dev/null

echo "APP_NAME=\"${APP_NAME}\""
echo "APP_NAME_LC=\"${APP_NAME_LC}\""
echo "BINARY_NAME=\"${BINARY_NAME}\""
echo "GH_REPO_PATH=\"${GH_REPO_PATH}\""
echo "ORG_NAME=\"${ORG_NAME}\""

echo "Applying patches from ../patches/*.patch..."
for file in ../patches/*.patch; do
  if [[ -f "${file}" ]]; then
    # Upstream drift regularly makes these patches stale.
    # - policies.patch: policy-watcher churn in package.json
    # - add-remote-url.patch: gulpfile JS->TS migration in upstream
    # Policy watcher lock is handled separately by patches/helper/apply_policy_watcher_lock.sh.
    if [[ "$(basename "${file}")" == "policies.patch" || "$(basename "${file}")" == "add-remote-url.patch" ]]; then
      echo "Skipping volatile patch: ${file}"
      continue
    fi
    apply_patch "${file}"
  fi
done

if [[ -x "../patches/helper/apply_policy_watcher_lock.sh" ]]; then
  ../patches/helper/apply_policy_watcher_lock.sh
fi

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  echo "Applying insider patches..."
  for file in ../patches/insider/*.patch; do
    if [[ -f "${file}" ]]; then
      apply_patch "${file}"
    fi
  done
fi

# An empty OS_NAME identifies the central Ubuntu compile job. Do not treat
# ../patches/ as an OS directory in that job or the root patches will run twice.
if [[ -n "${OS_NAME}" ]] && [[ -d "../patches/${OS_NAME}/" ]]; then
  echo "Applying OS patches (${OS_NAME})..."
  for file in "../patches/${OS_NAME}/"*.patch; do
    if [[ -f "${file}" ]]; then
      apply_patch "${file}"
    fi
  done
fi

echo "Applying user patches..."
for file in ../patches/user/*.patch; do
  if [[ -f "${file}" ]]; then
    apply_patch "${file}"
  fi
done

set -x

export ELECTRON_SKIP_BINARY_DOWNLOAD=1
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

if [[ "${OS_NAME}" == "linux" ]]; then
  export VSCODE_SKIP_NODE_VERSION_CHECK=1

   if [[ "${npm_config_arch}" == "arm" ]]; then
    export npm_config_arm_version=7
  fi
elif [[ "${OS_NAME}" == "windows" ]]; then
  if [[ "${npm_config_arch}" == "arm" ]]; then
    export npm_config_arm_version=7
  fi
elif [[ "${OS_NAME}" == "osx" ]]; then
  if [[ "${CI_BUILD}" != "no" ]]; then
    clang++ --version
  fi
fi

mv .npmrc .npmrc.bak
cp ../npmrc .npmrc

for i in {1..5}; do # try 5 times
  if [[ "${CI_BUILD}" != "no" && "${OS_NAME}" == "osx" ]]; then
    CXX=clang++ npm ci && break
  else
    npm ci && break
  fi

  echo "npm ci failed (attempt ${i}), trying npm install fallback..."
  if [[ "${CI_BUILD}" != "no" && "${OS_NAME}" == "osx" ]]; then
    CXX=clang++ npm install --no-audit --no-fund && break
  else
    npm install --no-audit --no-fund && break
  fi

  if [[ $i == 3 ]]; then
    echo "Npm install failed too many times" >&2
    exit 1
  fi
  echo "Npm install failed $i, trying again..."

  sleep $(( 15 * (i + 1)))
done

mv .npmrc.bak .npmrc

setpath() {
  local jsonTmp
  { set +x; } 2>/dev/null
  jsonTmp=$( jq --arg 'path' "${2}" --arg 'value' "${3}" 'setpath([$path]; $value)' "${1}.json" )
  echo "${jsonTmp}" > "${1}.json"
  set -x
}

setpath_json() {
  local jsonTmp
  { set +x; } 2>/dev/null
  jsonTmp=$( jq --arg 'path' "${2}" --argjson 'value' "${3}" 'setpath([$path]; $value)' "${1}.json" )
  echo "${jsonTmp}" > "${1}.json"
  set -x
}

# Merge the builder's product overrides into the Loophole IDE product metadata.
cp product.json{,.bak}

setpath "product" "documentationUrl" "https://loophole.dev"
setpath "product" "licenseUrl" "https://github.com/loophole-ai/loophole-ide/blob/main/LICENSE.txt"
setpath "product" "reportIssueUrl" "https://github.com/loophole-ai/loophole-ide/issues/new"
setpath "product" "requestFeatureUrl" "https://github.com/loophole-ai/loophole-ide/issues/new"
setpath "product" "releaseNotesUrl" "https://github.com/loophole-ai/loophole-ide/releases"
setpath "product" "updateUrl" "https://raw.githubusercontent.com/loophole-ai/versions/refs/heads/main"
setpath "product" "downloadUrl" "https://github.com/loophole-ai/loophole-ide/releases"

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "product" "nameShort" "Loophole - Insiders"
  setpath "product" "nameLong" "Loophole - Insiders"
  setpath "product" "applicationName" "loophole-insiders"
  setpath "product" "dataFolderName" ".loophole-insiders"
  setpath "product" "linuxIconName" "loophole-insiders"
  setpath "product" "quality" "insider"
  setpath "product" "urlProtocol" "loophole-insiders"
  setpath "product" "serverApplicationName" "loophole-server-insiders"
  setpath "product" "serverDataFolderName" ".loophole-server-insiders"
  setpath "product" "darwinBundleIdentifier" "com.loophole-ai.loophole-insiders"
  setpath "product" "win32AppUserModelId" "Loophole.LoopholeInsiders"
  setpath "product" "win32DirName" "Loophole Insiders"
  setpath "product" "win32MutexName" "loopholeinsiders"
  setpath "product" "win32NameVersion" "Loophole Insiders"
  setpath "product" "win32RegValueName" "LoopholeInsiders"
  setpath "product" "win32ShellNameShort" "Loophole Insiders"
else
  # Stable identity fields are maintained in loophole-ide/product.json.
  setpath "product" "quality" "stable"
fi

jsonTmp=$( jq -s '.[0] * .[1]' product.json ../product.json )
echo "${jsonTmp}" > product.json && unset jsonTmp

if [[ -n "${LOOPHOLE_VERSION:-}" ]]; then
  setpath "product" "loopholeVersion" "${LOOPHOLE_VERSION}"
fi

cat product.json

# Keep the Electron/VS Code base version separate from the Loophole product version.
cp package.json{,.bak}
package_source_version="${MS_TAG:-$(jq -r '.version' package.json)}"
package_version="$(ci_normalize_ms_tag "${package_source_version}")"
echo "package.json version: ${package_version} (MS_TAG=${MS_TAG:-not set})"
setpath "package" "version" "${package_version}"
setpath_json "package" "author" '{"name":"Loophole AI"}'

cp resources/server/manifest.json{,.bak}
if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  setpath "resources/server/manifest" "name" "Loophole - Insiders"
  setpath "resources/server/manifest" "short_name" "Loophole - Insiders"
else
  setpath "resources/server/manifest" "name" "Loophole"
  setpath "resources/server/manifest" "short_name" "Loophole"
fi

# announcements
# replace "s|\\[\\/\\* BUILTIN_ANNOUNCEMENTS \\*\\/\\]|$( tr -d '\n' < ../announcements-builtin.json )|" src/vs/workbench/contrib/welcomeGettingStarted/browser/gettingStarted.ts

"${REPO_ROOT}/scripts/undo_telemetry.sh"

# Escape non-ASCII chars that fail esbuild's minification integrity check.
# ›(U+203A) ❯(U+276F) ▸(U+25B8) ▶(U+25B6) appear as string/regex literals in
# some TS source files; esbuild only auto-converts them inside /regex/ literals,
# not inside quoted strings. Must be done after npm ci so ripgrep is available.
# Remove Copilot: make prepareBuiltInCopilotRipgrepShim a no-op when the
# extension or its SDK directory is absent (we don't install/bundle Copilot).
if [[ -f build/lib/copilot.ts ]]; then
  node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync} = require('fs');
const f = 'build/lib/copilot.ts';
let c = readFileSync(f, 'utf8');
// Replace the throw with a warn+return so build doesn't fail when Copilot is absent.
c = c.replace(
  "throw new Error(`[prepareBuiltInCopilotRipgrepShim] Copilot SDK directory not found at ${copilotSdkBase}`);",
  "console.warn('[prepareBuiltInCopilotRipgrepShim] Copilot SDK absent – shim skipped.'); return;"
);
writeFileSync(f, c);
console.log('patched build/lib/copilot.ts: shim is now optional');
NODEEOF
fi

# Remove extensions/copilot from the postinstall dirs so npm ci never installs it.
if [[ -f build/npm/dirs.ts ]]; then
  node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync} = require('fs');
const f = 'build/npm/dirs.ts';
let c = readFileSync(f, 'utf8');
c = c.replace(/^\s*'extensions\/copilot',?\n/m, '');
for (const ext of ['extensions/open-remote-ssh', 'extensions/open-remote-wsl']) {
  if (!c.includes(`'${ext}'`)) {
    c = c.replace(/(\t'remote',)/, `\t'${ext}',\n$1`);
  }
}
writeFileSync(f, c);
console.log('patched build/npm/dirs.ts: removed Copilot and ensured Loophole remote extensions');
NODEEOF
fi

echo "Escaping non-ASCII chars in TypeScript sources (esbuild minify guard)..."
node --input-type=commonjs - << 'NODEEOF'
const {readFileSync, writeFileSync, existsSync} = require('fs');
const {execSync} = require('child_process');
const CHARS = {'\u203a':'\\u203a', '\u276f':'\\u276f', '\u25b8':'\\u25b8', '\u25b6':'\\u25b6'};
const PATTERN = /[\u203a\u276f\u25b8\u25b6]/g;
const rg = './node_modules/@vscode/ripgrep/bin/rg';
const needle = '\u203a\u276f\u25b8\u25b6';
let files = [];
try {
  if (existsSync(rg)) {
    files = execSync(rg + " --no-ignore -l '[" + needle + "]' src/", {encoding:'utf8'}).trim().split('\n').filter(Boolean);
  } else {
    files = execSync("grep -rl --include='*.ts' '[" + needle + "]' src/ 2>/dev/null || true", {encoding:'utf8', shell:'/bin/bash'}).trim().split('\n').filter(Boolean);
  }
} catch { /* no matches — no files need fixing */ }
for (const f of files) {
  const orig = readFileSync(f, 'utf8');
  const fixed = orig.replace(PATTERN, c => CHARS[c]);
  if (fixed !== orig) { writeFileSync(f, fixed); console.log('fixed non-ASCII in:', f); }
}
NODEEOF

for electron_file in build/lib/electron.js build/lib/electron.ts; do
  if [[ -f "${electron_file}" ]]; then
    replace "s/companyName: (['\"])Microsoft Corporation\1/companyName: \1Loophole AI\1/" "${electron_file}"
  fi
done

# Copy the English-only Linux and Windows shell metadata from this builder.
if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  metadata_quality="insider"
else
  metadata_quality="stable"
fi
cp "../src/${metadata_quality}/resources/linux/code.desktop" resources/linux/code.desktop
cp "../src/${metadata_quality}/resources/linux/code-url-handler.desktop" resources/linux/code-url-handler.desktop
cp "../src/${metadata_quality}/resources/linux/code.appdata.xml" resources/linux/code.appdata.xml
cp "../src/${metadata_quality}/resources/win32/VisualElementsManifest.xml" resources/win32/VisualElementsManifest.xml

# Disable Microsoft's APT repository logic by making the non-code-oss branch match Loophole.
if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  sed -i "s/code-oss/loophole-insiders/" resources/linux/debian/postinst.template
else
  sed -i "s/code-oss/loophole/" resources/linux/debian/postinst.template
fi

# Linux package metadata.
sed -i 's|Visual Studio Code|Loophole|g' resources/linux/code.appdata.xml
sed -i 's|https://code.visualstudio.com/docs/setup/linux|https://loophole.dev|' resources/linux/code.appdata.xml
sed -i 's|https://code.visualstudio.com/home/home-screenshot-linux-lg.png|https://raw.githubusercontent.com/loophole-ai/loophole-ide/main/loophole_icons/loophole_banner_light.png|' resources/linux/code.appdata.xml
sed -i 's|https://code.visualstudio.com|https://loophole.dev|g' resources/linux/code.appdata.xml

sed -i 's|Microsoft Corporation <vscode-linux@microsoft.com>|Loophole AI <team@loophole.dev>|' resources/linux/debian/control.template
sed -i 's|Visual Studio Code|Loophole|g' resources/linux/debian/control.template
sed -i 's|https://code.visualstudio.com/docs/setup/linux|https://loophole.dev|' resources/linux/debian/control.template
sed -i 's|https://code.visualstudio.com|https://loophole.dev|g' resources/linux/debian/control.template

sed -i 's|Microsoft Corporation|Loophole AI|' resources/linux/rpm/code.spec.template
sed -i 's|Visual Studio Code Team <vscode-linux@microsoft.com>|Loophole AI <team@loophole.dev>|' resources/linux/rpm/code.spec.template
sed -i 's|Visual Studio Code|Loophole|g' resources/linux/rpm/code.spec.template
sed -i 's|https://code.visualstudio.com/docs/setup/linux|https://loophole.dev|' resources/linux/rpm/code.spec.template
sed -i 's|https://code.visualstudio.com|https://loophole.dev|g' resources/linux/rpm/code.spec.template

for desktop_file in resources/linux/code.desktop resources/linux/code-url-handler.desktop; do
  if [[ -f "${desktop_file}" ]]; then
    sed -i 's|Keywords=.*|Keywords=loophole;loophole-editor;ai;vscode;|' "${desktop_file}"
    sed -i '/^Name\[[^]]*\]=/d' "${desktop_file}"
  fi
done

# Windows package metadata.
if [[ -f resources/win32/VisualElementsManifest.xml ]]; then
  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    sed -i 's|ShortDisplayName="[^"]*"|ShortDisplayName="Loophole - Insiders"|' resources/win32/VisualElementsManifest.xml
  else
    sed -i 's|ShortDisplayName="[^"]*"|ShortDisplayName="Loophole"|' resources/win32/VisualElementsManifest.xml
  fi
fi
sed -i 's|https://code.visualstudio.com|https://loophole.dev|g' build/win32/code.iss
sed -i 's|Microsoft Corporation|Loophole AI|g' build/win32/code.iss

cd ..
