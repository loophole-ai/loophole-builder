# Extension compatibility

Loophole uses the Open VSX registry by default. Most VS Code-compatible extensions work normally, but extensions that hard-code Microsoft services, proprietary marketplace endpoints, or Microsoft-specific authentication can require an alternative.

## Common limitations

- Extensions that require a Visual Studio subscription may not work without the required entitlement.
- Extensions that bundle or expect Microsoft's proprietary debugging components may not work on every platform.
- Extensions that call the Microsoft Marketplace directly may not work with the default Open VSX configuration.
- Extensions that require a Visual Studio installation are not supported by the Linux or macOS builds.

## Open VSX alternatives

- [Open Remote - SSH](https://open-vsx.org/extension/jeanp413/open-remote-ssh)
- [Open Remote - WSL](https://open-vsx.org/extension/jeanp413/open-remote-wsl)
- [BasedPyright](https://open-vsx.org/extension/detachhead/basedpyright)

## Reporting an issue

When an extension fails, include the extension ID, Loophole version, operating system, architecture, and the relevant extension-host log. Confirm whether the same extension works in another VS Code-compatible editor before classifying it as a Loophole packaging issue.
