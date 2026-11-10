#!/usr/bin/env bash
#---------------------------------------------------------------------------------------
#  Copyright 2026 Loophole AI. All rights reserved.
#  Licensed under the AGPL-3.0 License. See LICENSE.txt for more information.
#---------------------------------------------------------------------------------------
#
# upload-to-gofile.sh <file-to-upload>
#
# Uploads one built asset to gofile.io and prints the share link. Used by CI so a
# finished installer can be fetched straight from a CDN instead of pulled through
# GitHub's artifact service, which is slow for a ~500 MB exe.
#
# API notes, learned the hard way and verified against the live service:
#   - endpoint is POST https://upload.gofile.io/uploadfile
#   - the multipart field is "file" (SINGULAR). Sending "files" returns the
#     literal body "error-file" and no JSON, which is easy to misread as success.
#   - no token is needed; gofile creates a guest account per upload.
#   - the response carries data.downloadPage, which is already a share link of the
#     form https://gofile.io/d/<code>. Use it verbatim. Do not try to build a
#     direct /dl or /w link: those undocumented paths 404 on the current service.
#   - do not call the servers endpoint; upload.gofile.io already routes to the
#     best region, and api.gofile.io/servers rate-limits to one call per 10s.
#
# The link is public and unlisted: anyone with it can download. Guest uploads are
# subject to gofile's retention and cold-storage rules, so treat this as a fast
# transfer of a build that also exists in GitHub artifacts, not as storage.

set -euo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
	echo "usage: upload-to-gofile.sh <file>" >&2
	exit 2
fi
if [[ ! -f "$FILE" ]]; then
	echo "::error::no such file: $FILE" >&2
	exit 2
fi

size=$(wc -c <"$FILE" | tr -d ' ')
name=$(basename "$FILE")
echo "uploading $name ($size bytes)"

# Large installers (~260 MB) frequently hit gofile's 5xx / 500 / connection resets
# on a single attempt (observed: "500" + "error-createFolderResponse" on a
# 263 MB exe). Retry with fresh TCP connections and, after several direct
# failures, fall back to a specific edge server picked from api.gofile.io/servers
# (the direct upload.gofile.io host itself routes per request, so both paths
# are exercised). --retry-all-errors retries on 5xx and network errors alike.
# No token is needed; gofile creates a guest account per upload.
post_attempt() {
	local host="$1"
	local out
	if ! out=$(curl -sS -L --fail-with-body \
		--retry 5 --retry-all-errors --retry-delay 5 \
		--connect-timeout 60 --max-time 3600 \
		-X POST "${host}/contents/uploadfile" \
		-F "file=@${FILE}" 2>&1); then
		echo "ATTEMPT_FAILED ${host}: ${out}" >&2
		return 1
	fi
	case "$out" in
	'{'*) ;;
	*)
		echo "ATTEMPT_NOT_JSON ${host}: ${out}" >&2
		return 1
		;;
	esac
	printf '%s' "$out"
}

response=""
for attempt in 1 2 3; do
	response=$(post_attempt 'https://upload.gofile.io') && break
	echo "::warning::direct gofile upload attempt ${attempt} failed; retrying" >&2
done

if [[ -z "$response" ]]; then
	# Fallback: a specific edge server from the servers list (avoid the rate
	# limit by picking only once, never in a loop).
	server=$(curl -sS --max-time 30 'https://api.gofile.io/servers' \
		| node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s);const list=(j.data&&j.data.servers)||[];console.log(list[0]&&list[0].name||"")}catch{console.log("")}})')
	if [[ -n "$server" ]]; then
		echo "::warning::direct host failed 3 times; trying edge server ${server}" >&2
		response=$(post_attempt "https://${server}.gofile.io") || response=""
	fi
fi

if [[ -z "$response" ]]; then
	echo "::error::upload request failed on every attempt" >&2
	exit 1
fi

case "$response" in
'{'*) ;;
*)
	echo "::error::unexpected upload response (not JSON): $response" >&2
	exit 1
	;;
esac

# Parse with jq when it is on PATH, otherwise with node. Both are present on the
# runners, but jq is not guaranteed everywhere, and depending on it silently
# turned a successful upload into exit 127.
if command -v jq >/dev/null 2>&1; then
	page=$(printf '%s' "$response" | jq -r '.data.downloadPage // empty')
	status=$(printf '%s' "$response" | jq -r '.status // empty')
else
	parsed=$(printf '%s' "$response" | node -e '
		let s = "";
		process.stdin.on("data", d => s += d);
		process.stdin.on("end", () => {
			try {
				const j = JSON.parse(s);
				process.stdout.write((j.status || "") + "\n" + ((j.data && j.data.downloadPage) || ""));
			} catch { process.stdout.write("\n"); }
		});
	')
	status=$(printf '%s' "$parsed" | head -n1)
	page=$(printf '%s' "$parsed" | tail -n1)
fi

if [[ "$status" != "ok" || -z "$page" ]]; then
	echo "::error::gofile reported status='$status' and no downloadPage" >&2
	echo "$response" >&2
	exit 1
fi

echo ""
echo "gofile status : $status"
echo "gofile link   : $page"
echo "file          : $name"
echo "size          : $size bytes"

# The download page is the useful output. Echo it bare as well so it is trivial
# to copy out of a CI log, and mirror it into the job summary.
echo ""
echo "DOWNLOAD_URL=$page"
{
	echo "## Installer ready"
	echo ""
	echo "**$name** - $size bytes"
	echo ""
	echo "[Download from gofile.io]($page)"
} >>"$GITHUB_STEP_SUMMARY"

echo "::notice title=Installer uploaded::$page"
