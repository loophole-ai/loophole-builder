# Loophole Builder

Loophole Builder compiles the [Loophole IDE](https://github.com/loophole-ai/loophole-ide) source into signed desktop binaries and publishes them through GitHub Actions.

The repository is based on the upstream VSCodium-compatible packaging toolchain. Loophole-specific branding, versioning, release assets, and update metadata are maintained here.

## Responsibilities

- Clones the `loophole-ai/loophole-ide` repository.
- Applies privacy, packaging, Linux, Windows, and remote-server patches.
- Builds Windows installers, macOS DMG/ZIP files, Linux archives, and REH server archives.
- Publishes assets to `loophole-ai/loophole-ide` releases.
- Updates the arch-based update feed in `loophole-ai/versions`.

## Local checkout

```bash
git clone https://github.com/loophole-ai/loophole-builder.git
cd loophole-builder
nvm install
nvm use
```

The repository's `.nvmrc` selects the Node.js version used by the IDE build.

The main entry points are:

- `ci_check.sh`: selects the source and release version.
- `prepare_vscode.sh`: generates icons and configures the IDE source tree.
- `build.sh`: compiles the editor and remote-server sources.
- `prepare_assets.sh`: creates release archives and installers.
- `release.sh`: creates the GitHub release and uploads assets.
- `update_version.sh`: publishes `latest.json` files to `loophole-ai/versions`.

See [`docs/SCRIPTS.md`](docs/SCRIPTS.md) for the pipeline map and [`docs/howto-build.md`](docs/howto-build.md) for local build requirements.

## Release versioning

Loophole releases use standalone semantic versions such as `2.2.3`. The version is stored as `loopholeVersion` in the IDE product metadata. The underlying VS Code version remains in `package.json` and is tracked separately as `MS_TAG`.

The updater expects these feed paths:

```text
stable/darwin/{arch}/latest.json
stable/linux/{arch}/latest.json
stable/win32/{arch}/system/latest.json
stable/win32/{arch}/user/latest.json
stable/win32/{arch}/archive/latest.json
stable/win32/{arch}/msi/latest.json
```

## Maintenance

When rebasing onto newer VS Code or upstream builder sources, review case-sensitive `Loophole` and `loophole` references, rerun shell/YAML validation, and build at least one artifact for every supported platform before publishing a release.
