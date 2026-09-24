# Loophole Builder documentation

Loophole Builder packages the Loophole IDE source into desktop installers and remote-server archives.

## Documentation

- [Build Loophole](howto-build.md)
- [Pipeline scripts](SCRIPTS.md)
- [Troubleshooting](troubleshooting.md)
- [Extension compatibility](extensions-compatibility.md)
- [Account authentication](accounts-authentication.md)
- [Contributing](../CONTRIBUTING.md)

## Build model

The builder uses three related version values:

- `MS_TAG`: the underlying VS Code version used to compile the source.
- `LOOPHOLE_VERSION`: the standalone Loophole product version stored in `loopholeVersion`.
- `RELEASE_VERSION`: the GitHub release tag, normally equal to `LOOPHOLE_VERSION`.

Keeping the VS Code base version and Loophole product version separate allows the editor to be rebased without changing the public Loophole release version.

## Platform outputs

| Platform | Primary assets |
|---|---|
| Windows | User EXE, system EXE, ZIP, and x64 MSI packages |
| macOS | Signed and notarized DMG plus optional ZIP |
| Linux | Architecture-specific tar.gz archives |
| Remote server | Linux and Windows REH/REH-web tar.gz archives |

The default CI release path publishes Windows, macOS, Linux, and Linux REH assets. Other package formats are maintained as optional local packaging paths.

## Update metadata

After assets are uploaded, `update_version.sh` writes architecture-based `latest.json` files to `loophole-ai/versions`. The IDE reads this static repository to discover installers and archives without relying on the old VSCodium update API.

## Privacy and telemetry

The builder applies patches that disable Microsoft telemetry endpoints, set telemetry defaults to off, use Open VSX, and point product links to Loophole resources. Review new patches carefully to ensure they do not reintroduce Microsoft service calls or old product branding.

## Repository maintenance

When updating from the upstream builder sources:

1. Rebase on matching VS Code and upstream builder versions.
2. Review every case-sensitive `Loophole` and `loophole` reference.
3. Regenerate platform icons.
4. Validate shell scripts and workflow YAML.
5. Build one artifact for every supported architecture.
6. Test the generated `latest.json` paths before publishing.
