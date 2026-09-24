# Troubleshooting Loophole Builder

## A patch does not apply

Run the build with shell tracing enabled or apply the patch manually:

```bash
cd vscode
git apply --reject ../patches/<patch-name>.patch
```

Resolve every generated `.rej` file, then regenerate the patch with `dev/update_patches.sh`. The builder intentionally skips known volatile patches and reports each skipped file; do not treat a skipped patch as successfully applied.

## Icon generation fails

Verify that the IDE source exists and the required tools are available:

```bash
command -v convert
command -v png2icns
./icons/build_icons.sh
```

On Ubuntu, install `imagemagick` and `icoutils`. The icon script intentionally fails when an input Loophole logo is missing.

## npm installation fails

The CI workflows use the Node.js version from `.nvmrc` and pin npm below the incompatible major release. Reproduce that environment locally:

```bash
nvm install
nvm use
npm install -g "npm@<11.2.0"
```

The build retries `npm ci` and then falls back to `npm install` for the main source tree. Preserve the captured npm debug logs when diagnosing CI failures.

## A GitHub release asset already exists

`release.sh` retries uploads and removes a conflicting asset before retrying. If a manual retry still fails, inspect the release with:

```bash
gh release view "$RELEASE_VERSION" --repo loophole-ai/loophole-ide
gh release upload --repo loophole-ai/loophole-ide "$RELEASE_VERSION" <asset>
```

Never upload a different architecture under an existing architecture-specific name.

## The versions repository push conflicts

`update_version.sh` rebases and retries concurrent platform updates. A persistent conflict usually means another process changed the same `latest.json` path. Stop parallel deployments, pull `loophole-ai/versions`, and rerun the failed platform job with `force_version` enabled.

## The IDE cannot see a new release

The IDE reads static metadata from:

```text
https://raw.githubusercontent.com/loophole-ai/versions/refs/heads/main
```

Verify all of the following:

1. The GitHub release tag matches `RELEASE_VERSION`.
2. The asset name and architecture match the platform matrix.
3. The corresponding `latest.json` exists under the arch-based path.
4. `productVersion` is a valid semantic version.
5. `url` points to an asset that is publicly downloadable.

Common paths are listed in `docs/SCRIPTS.md`.

## Windows MSI build fails

Check that WiX Toolset 3 is installed and available through the `WIX` environment variable. The MSI build expects an English localization file at `build/windows/msi/i18n/loophole.en-us.wxl` and a generated `vscode/resources/win32/code.ico`.

## macOS signing or notarization fails

Confirm that all certificate secrets use the `CERTIFICATE_OSX_NEW_*` names and that the temporary keychain can be created. The workflow signs the application before creating the DMG and submits the temporary ZIP to Apple notarization.

## Linux native modules fail to compile

Confirm the Node.js architecture, compiler architecture, and package dependencies match `VSCODE_ARCH`. Cross-architecture builds may require a matching sysroot or native runner. The hosted workflow currently publishes tar.gz assets and does not build DEB, RPM, or AppImage packages.
