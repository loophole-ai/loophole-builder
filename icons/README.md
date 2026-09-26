# Loophole icon assets

`build_icons.sh` generates application and file icons directly in the checked-out `vscode/` tree.

| File | Purpose |
|---|---|
| `template_macos.png` | Source image for the macOS application icon |
| `stable/loophole_logo.png` | Stable-channel Loophole app icon (rounded square) used as the source for every generated icon |
| `stable/onboarding_logo180.png` | Stable onboarding image (light mark, sits on a coloured surface) |
| `stable/loophole_banner_dark.png` | Stable dark-theme banner source |
| `stable/loophole_banner_light.png` | Stable light-theme banner source |
| `stable/inno/inno-*.bmp` | Stable Inno Setup wizard bitmaps (`WizardImageFile` / `WizardSmallImageFile`) |
| `insider/loophole_logo.png` | Insider-channel Loophole app icon (rounded square) used as the source for every generated icon |
| `insider/onboarding_logo180.png` | Insider onboarding image (light mark, sits on a coloured surface) |
| `insider/loophole_banner_dark.png` | Insider dark-theme banner source |
| `insider/loophole_banner_light.png` | Insider light-theme banner source |
| `insider/inno/inno-*.bmp` | Insider Inno Setup wizard bitmaps (`WizardImageFile` / `WizardSmallImageFile`) |

The `loophole_logo.png` files are the full app icon (dark rounded square with the
light mark), matching `template_macos.png` and the IDE's `loophole_icons/logo.png`.
Generating icons from a bare light mark instead left the Windows `.ico`, the
Linux/server PNGs and the workbench SVGs effectively invisible on light
backgrounds.

The `inno/*.bmp` files are copied verbatim, not generated. The big bitmaps are a
full-bleed banner carrying the wordmark and the small ones are the rounded app
icon, so neither can be produced from a single square logo; rendering the logo
onto a white canvas is what made the installer wizard show a blank white panel.

## Generated outputs

The script updates:

- macOS `.icns` application and language icons
- Linux PNG/XPM application icons
- Windows `.ico`, PNG, and installer bitmap assets
- Remote-server favicon and PNG assets
- Workbench and editor SVG/PNG brand assets

Required tools are ImageMagick, icoutils (`png2icns`), and `base64`. The selected channel comes from `VSCODE_QUALITY` and defaults to `stable`.
