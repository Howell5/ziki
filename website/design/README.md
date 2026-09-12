# Website art sources

Generated with the **built-in imagegen tool** for this website. No CLI provider or stock reference used. The originals are retained here; only resized/compressed exports are served. The native desktop app icon is unchanged.

## `ink-landscape.png`

Prompt:

> Create an original contemporary Chinese ink-wash landscape illustration for the Ziki macOS speech-to-text website, inspired by Boya and Ziqi and the idea of listening and being understood. Wide landscape 1536x1024. A single low abstract mountain silhouette with delicate dry-brush edges on the right, its dark pine-green-black ink dissolving into quiet pale gray mist and a few very fine horizontal water lines below. Modern gallery editorial art, extremely restrained, sophisticated minimalist new-Chinese aesthetic, not traditional decorative painting. Background perfectly warm ivory #f7f6f2, opaque, no antique yellowing or heavy paper texture. Large quiet negative space in left half and top third, all expressive marks grounded in lower-right half. No people, architecture, birds, trees, sun, red seal, calligraphy, text, border, or mockup. Natural hand-made ink granulation only within the mountain. Calm and precise, subtle atmospheric depth, no gradients outside the natural ink wash. One complete art asset.

Export: `cwebp -q 83 design/ink-landscape.png -o public/ink-landscape.webp`.

## `ziki-ink.png`

Prompt:

> Design an original minimal ink-brush Z logo for Ziki, a contemporary macOS app named after Ziqi and the ancient story of a listener who understands the music. Single square 1024x1024 brand symbol on perfectly opaque warm ivory #f7f6f2. A clearly legible uppercase Z formed by two complementary thick black-ink ribbon brushstrokes, separated by a slim diagonal negative-space slit. Graceful rounded turns, small dry-brush feathering at tips only, solid coherent center, bold silhouette readable at 24px. The two gestures echo each other like resonating strings. Contemporary premium editorial identity, NOT a historical Chinese calligraphy character. Symbol fills 75 percent of canvas, centered with equal padding. No words, no seal, no instruments, no circle, no gradients, no mockup, no other marks. Refined hand-brushed tension rather than messy paint splatter.

Exports: `sips -Z 256 design/ziki-ink.png --out public/ziki-mark.png` and `sips -Z 64 design/ziki-ink.png --out public/favicon.png`.
