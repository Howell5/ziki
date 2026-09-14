# Website art sources

The website's visual language is paper and ink: quiet warm ivory space, a
restrained black brush mark, and sparse ink-wash atmosphere. The files in this
directory are the retained source images. Website exports may be resized or
compressed, but the source images are not redrawn in the export step.

## `ziki-ink.png`

This is the shared Ziki identity master. It is a square, opaque warm-ivory
paper field with one black brush Z: two complementary strokes, a diagonal
negative-space slit, and restrained feathering at the tips. The native app
uses this same source, downscaled to `Packaging/Assets/ZikiIcon-1024.png` and
then exported to the normal macOS icon sizes. The transparent menu-bar
cutout is documented with the native assets in `Packaging/Assets/README.md`.

Prompt:

> Design an original minimal ink-brush Z logo for Ziki, a contemporary macOS app named after Ziqi and the ancient story of a listener who understands the music. Single square 1024x1024 brand symbol on perfectly opaque warm ivory #f7f6f2. A clearly legible uppercase Z formed by two complementary thick black-ink ribbon brushstrokes, separated by a slim diagonal negative-space slit. Graceful rounded turns, small dry-brush feathering at tips only, solid coherent center, bold silhouette readable at 24px. The two gestures echo each other like resonating strings. Contemporary premium editorial identity, NOT a historical Chinese calligraphy character. Symbol fills 75 percent of canvas, centered with equal padding. No words, no seal, no instruments, no circle, no gradients, no mockup, no other marks. Refined hand-brushed tension rather than messy paint splatter.

## `ink-landscape.png`

This is a separate website atmosphere source: a restrained contemporary ink-
wash landscape with the expressive marks grounded in the lower-right half and
quiet paper space elsewhere.

Prompt:

> Create an original contemporary Chinese ink-wash landscape illustration for the Ziki macOS speech-to-text website, inspired by Boya and Ziqi and the idea of listening and being understood. Wide landscape 1536x1024. A single low abstract mountain silhouette with delicate dry-brush edges on the right, its dark pine-green-black ink dissolving into quiet pale gray mist and a few very fine horizontal water lines below. Modern gallery editorial art, extremely restrained, sophisticated minimalist new-Chinese aesthetic, not traditional decorative painting. Background perfectly warm ivory #f7f6f2, opaque, no antique yellowing or heavy paper texture. Large quiet negative space in left half and top third, all expressive marks grounded in lower-right half. No people, architecture, birds, trees, sun, red seal, calligraphy, text, border, or mockup. Natural hand-made ink granulation only within the mountain. Calm and precise, subtle atmospheric depth, no gradients outside the natural ink wash. One complete art asset.

Export: `cwebp -q 83 design/ink-landscape.png -o public/ink-landscape.webp`.

The mark exports are made from `ziki-ink.png`, for example:

```sh
sips -Z 256 design/ziki-ink.png --out public/ziki-mark.png
sips -Z 64 design/ziki-ink.png --out public/favicon.png
```
