# Ziki website

A bilingual, statically prerendered product site built with TanStack Start, React, TypeScript, and plain CSS. English lives at `/`; Chinese at `/zh/`. No API server, CMS, analytics, microphone access, or AI calls. The interactive dictation examples are explicitly labeled illustrations.

## Develop and verify

Requires Node.js 24 and npm.

```sh
cd website
npm ci
npm run dev
```

Production checks (build first, since it generates the TanStack route tree and the HTML tested below):

```sh
npm run build
npm run check
npm test
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist/client
```

Open `http://127.0.0.1:4173` to verify that the built site works with a plain static server. Publish **only `dist/client/`** to a static host; it contains both pre-rendered HTML pages, fonts, scripts and images. Do not deploy `dist/server/`; it is a build-time artifact.

The host must serve directory indexes (`/zh/` → `/zh/index.html`) and normal 404 responses, not rewrite every path to the English homepage. Hosting and a canonical public domain are deliberately not configured yet. Once the domain is chosen, add absolute canonical/hreflang URLs, social image metadata, and a sitemap for that origin. No domain is invented in this build.

An inactive [GitHub Actions example](ci-workflow.example.yml) is included. A maintainer with workflow-write permission can install it as `.github/workflows/website.yml` to build, check, and upload a `ziki-static-website` artifact. It does not deploy publicly or publish desktop releases. The current delivery token lacks the `workflow` scope, so no active workflow was added. See [QA.md](QA.md) for the completed local verification.

## Maintain

- Update the current downloadable release in `src/content.ts`, including both preview labels. Keep the exact GitHub asset URL and verify it exists before publishing. The website does not query GitHub on every visit.
- Main site copy is a typed English/Chinese object. Route-specific SEO metadata lives in `src/routes/index.tsx` and `src/routes/zh.tsx`.
- `Brand.tsx` owns the hover, focus, click, Escape, and outside-dismiss story card. A short brand origin is also permanently visible below the product details.
- `Demo.tsx` owns the opt-in, cancelable sample playback. Changing scenarios clears the pending stage timer. Reduced-motion settings disable animation.
- The site fonts are bundled and served locally. No runtime third-party font request is made.
- App code, package identity, signing, and releases are unchanged by this website.

## Art direction

Warm ivory, ink black and pine green; contemporary editorial layout with restrained Chinese ink details. Original brand art was generated using the built-in image generation tool, not a stock image or an app screenshot. See [design/README.md](design/README.md) for prompts and source assets.

Production assets are `public/ink-landscape.webp`, `public/ziki-mark.png`, and `public/favicon.png`. Original PNGs in `design/` are not shipped. DM Sans and Instrument Serif are distributed by Fontsource under their respective SIL Open Font Licenses; copies are served in `public/licenses/`.
