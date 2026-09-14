# Ziki brand assets

Ziki's native identity is a black brush mark on warm ivory paper. The mark is
the existing website master at `website/design/ziki-ink.png`; it is the source
for the app icon, rather than a separately redrawn native logo. The paper is
opaque and warm ivory, while the ink remains visually neutral black/gray.

## Source and exports

- `website/design/ziki-ink.png` is the shared square master.
- `ZikiIcon-1024.png` is the master downscaled to 1024×1024 for the native
  icon. The checked-in `AppIcon.iconset/` contains the normal `iconutil`
  exports from that icon, and `AppIcon.icns` is the resulting bundle asset.
- `ZikiMenuBarMaster.png` is the transparent cutout master made from the same
  original mark. `ZikiMenuBarTemplate.png` is its 36×36 menu bar export.

The menu template was generated with the built-in imagegen cutout flow and
saved as `ZikiMenuBarMaster.png`. Builds need only this checked-in source,
not the original generation environment. Its prompt was:

> Extract the EXACT black brush Z from its ivory background onto genuine alpha transparency. Preserve exact original silhouette, two complementary strokes, diagonal negative-space slit, all proportions, placement, size, tip feathering. No redesign, no added marks, no text, no shadow, no panel. Square transparent PNG menu bar template master; ink should be black and background completely transparent including diagonal slit. Preserve generous equal margins as in original.

To regenerate the ordinary macOS icon sizes from the checked-in 1024 icon,
use the repository asset generator and `iconutil`:

```sh
swift scripts/generate-brand-assets.swift
```

That process performs resizing/export only. It does not redraw the mark or
call an image service. Verify the source colors, app-icon correspondence,
dimensions, and menu-template alpha with:

```sh
swift scripts/verify-brand.swift
```
