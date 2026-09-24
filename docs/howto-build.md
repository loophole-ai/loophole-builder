# How to build Loophole

## Recommended build method

The supported release path is the `Loophole Builder CI` GitHub Actions workflow. It checks out the IDE source, applies the builder patches, compiles once, creates platform assets, publishes a GitHub release, and updates `loophole-ai/versions`.

A complete build is resource-intensive and can take a long time. Ensure the runner has enough free disk space for the IDE source, native modules, and platform outputs.

## Common dependencies

- Node.js from `.nvmrc`
- npm
- Git
- jq
- Python 3.11 or newer
- ImageMagick (`convert`)
- icoutils (`png2icns`)

## Linux

Install the build and native-module dependencies:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential curl git jq pkg-config \
  libkrb5-dev libsecret-1-dev libxkbfile-dev \
  imagemagick icoutils
```

Additional DEB, RPM, AppImage, or Snap dependencies are required only for those optional formats.

## macOS

Install the command-line tools, Homebrew, and icon dependencies:

```bash
xcode-select --install
brew install jq imagemagick icoutils
```

Set `NODE_OPTIONS=--max-old-space-size=8192` for large builds.

## Windows

Use Git for Windows Bash and install:

- Node.js from `.nvmrc`
- Python 3.12
- 7-Zip
- WiX Toolset 3
- Native build tools required by VS Code

Run shell scripts from Git Bash.

## Local convenience build

```bash
nvm install
nvm use
./dev/build.sh
```

Packaging flags:

- `-i`: build the Insider quality
- `-o`: skip compilation
- `-p`: generate package assets
- `-s`: reuse the existing source checkout

For example:

```bash
./dev/build.sh -p
```

The wrapper stores checkout metadata in `dev/build.env`. Do not commit that file.

`release.sh` and `update_version.sh` require a GitHub token with write access to the release repository and `loophole-ai/versions`.

## Icon generation

`icons/build_icons.sh` writes generated assets into `vscode/`. It requires:

- ImageMagick
- icoutils (`png2icns`)
- `base64`

The script generates application icons, file-language icons, server images, the workbench mark, onboarding image, Windows installer bitmaps, and embedded SVG assets.

## Updating patches

Use `dev/update_patches.sh` to reapply patches after upstream changes. Resolve every `.rej` file, run the relevant IDE checks, and regenerate patches only after the source tree builds successfully.

## Optional Snap packaging

Snap definitions are maintained under:

```text
stores/snapcraft/stable
stores/snapcraft/insider
```

Build them with Snapcraft on a compatible Ubuntu environment. Snap builds download a published Loophole DEB release; they are not part of the default GitHub Actions release path.
