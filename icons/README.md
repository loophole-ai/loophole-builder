# Loophole icon assets

`build_icons.sh` generates application and file icons directly in the checked-out `vscode/` tree.

| File | Purpose |
|---|---|
| `template_macos.png` | Source image for the macOS application icon |
| `stable/loophole_logo.png` | Stable-channel Loophole mark |
| `stable/onboarding_logo180.png` | Stable onboarding image |
| `stable/loophole_banner_dark.png` | Stable dark-theme banner source |
| `stable/loophole_banner_light.png` | Stable light-theme banner source |
| `insider/loophole_logo.png` | Insider-channel Loophole mark |
| `insider/onboarding_logo180.png` | Insider onboarding image |
| `insider/loophole_banner_dark.png` | Insider dark-theme banner source |
| `insider/loophole_banner_light.png` | Insider light-theme banner source |

## Generated outputs

The script updates:

- macOS `.icns` application and language icons
- Linux PNG/XPM application icons
- Windows `.ico`, PNG, and installer bitmap assets
- Remote-server favicon and PNG assets
- Workbench and editor SVG/PNG brand assets

Required tools are ImageMagick, icoutils (`png2icns`), and `base64`. The selected channel comes from `VSCODE_QUALITY` and defaults to `stable`.
