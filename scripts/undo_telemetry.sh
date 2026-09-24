#!/usr/bin/env bash
# Disable Microsoft telemetry endpoints in the IDE source tree.

set -e

SEARCH='\.data\.microsoft\.com'
REPLACEMENT='s|//[^/]+\.data\.microsoft\.com|//0.0.0.0|g'

if [[ -z "${LOOPHOLE_BUILDER_ROOT:-}" ]]; then
  LOOPHOLE_BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export LOOPHOLE_BUILDER_ROOT
fi
# shellcheck source=scripts/lib/utils.sh
. "${LOOPHOLE_BUILDER_ROOT}/scripts/lib/utils.sh"

replace_with_debug() {
  local expression="$1"
  local file="$2"
  echo "Blocking telemetry endpoint in: ${file}"
  replace "${expression}" "${file}"
}

echo "----------- undo telemetry -----------"
start_time=$(date +%s)

RG_EXCLUDE=(
  --glob '!out/**'
  --glob '!out-build/**'
  --glob '!out-vscode/**'
  --glob '!out-vscode-min/**'
  --glob '!.build/**'
  --glob '!node_modules/**'
)
GREP_EXCLUDE=(
  --exclude-dir=.git
  --exclude-dir=out
  --exclude-dir=out-build
  --exclude-dir=out-vscode
  --exclude-dir=out-vscode-min
  --exclude-dir=.build
  --exclude-dir=node_modules
)

files=""
if [[ -x ./node_modules/@vscode/ripgrep/bin/rg ]]; then
  files=$(./node_modules/@vscode/ripgrep/bin/rg --no-ignore "${RG_EXCLUDE[@]}" -l "${SEARCH}" . || true)
else
  files=$(grep -rl "${GREP_EXCLUDE[@]}" -E "${SEARCH}" . || true)
fi

if [[ -z "${files}" ]]; then
  echo "No Microsoft telemetry endpoints remain"
else
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    replace_with_debug "${REPLACEMENT}" "${file}"
  done <<< "${files}"
fi

end_time=$(date +%s)
echo "undo_telemetry: $((end_time - start_time))s"
