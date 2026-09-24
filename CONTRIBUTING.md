# Contributing to Loophole Builder

Thank you for helping improve Loophole Builder.

## Code of Conduct

Everyone participating in this project is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs

Before opening an issue:

1. Search the existing issues in `loophole-ai/loophole-builder`.
2. Check [Troubleshooting](docs/troubleshooting.md).
3. Include the builder commit, Loophole IDE commit, operating system, architecture, Node.js version, and the failing workflow step.
4. Include sanitized workflow logs. Never post access tokens, signing certificates, or private repository credentials.

## Development setup

```bash
git clone https://github.com/loophole-ai/loophole-builder.git
cd loophole-builder
nvm install
nvm use
```

Read [How to build Loophole](docs/howto-build.md) before starting a full build.

## Making changes

- Keep the default stable channel and existing artifact names unless a release migration is intentional.
- Use standalone Loophole semantic versions for `LOOPHOLE_VERSION` and `RELEASE_VERSION`.
- Keep the VS Code base version in `MS_TAG` and `package.json`.
- Update both the artifact name and its `loophole-ai/versions` path together.
- Write scripts, comments, workflow labels, and documentation in English.
- Do not rename technical upstream identifiers such as `@vscodium/policy-watcher` unless the upstream dependency itself changes.

## Updating patches

1. Run the build and identify the failing patch.
2. Use `dev/update_patches.sh` to reapply the patch set.
3. Resolve all `.rej` files against the current IDE source.
4. Run compilation before accepting a regenerated patch.
5. Review the final diff for unrelated changes.

## Validation

Before opening a pull request, run the repository's shell syntax checks, workflow YAML validation, and the most relevant local packaging command. A change to product identity, versioning, release naming, or update metadata requires a full artifact review.
