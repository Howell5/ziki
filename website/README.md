# Ziki website

A bilingual, statically prerendered product site built with TanStack Start, React, TypeScript, and plain CSS. English lives at `/`; Chinese at `/zh/`. No API server, CMS, analytics, microphone access, or AI calls. The interactive dictation examples are explicitly labeled illustrations.

Production: [English](https://getziki.com) · [简体中文](https://getziki.com/zh/), hosted on Cloudflare Workers Static Assets.

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

## Production deployment

`wrangler.jsonc` deploys only `dist/client/` to the `ziki-website` Worker and binds `getziki.com` and `www.getziki.com`. There is no server Worker, database, or app API migration. Directory indexes are enabled; unknown paths return the branded 404 page with HTTP 404, not the homepage. Public `workers.dev` and preview URLs are disabled.

Cloudflare Workers Builds is connected directly to `Howell5/ziki`, with:

- Production branch: `main`; changed-path filter: `website/**`.
- Root directory: `website`; Node.js: `24.19.0`.
- Build command: `npm run build && npm run check && npm test`.
- Deploy command: `npx wrangler deploy`.

The integration is configured in Cloudflare, not GitHub Actions. The inactive [Actions example](ci-workflow.example.yml) remains optional and is not used for production deployment. Build credentials stay in Cloudflare; do not commit tokens or `.dev.vars`.

For a manual deployment with an authorized Cloudflare login, run from `website/`:

```sh
npm ci
npm run deploy
```

The zone-level **Ziki canonical hostname** redirect rule sends HTTP and `www` requests to `https://getziki.com`, preserving their path and query string with HTTP 301. This is a Cloudflare control-plane setting, not part of Wrangler configuration: recreate it if moving to another zone. Its expression is `(http.host eq "www.getziki.com") or (http.host eq "getziki.com" and not ssl)`, targeting `concat("https://getziki.com", http.request.uri.path)` with query preservation. `public/_redirects` handles the path-only `/zh` → `/zh/` redirect.

Canonical URLs, reciprocal language alternates, and social sharing metadata use the production origin. `public/robots.txt` advertises the two-language sitemap. Search Console verification/submission and search-engine indexing are separate steps and have not been performed. See [QA.md](QA.md) for verification evidence.

## Maintain

- Update the current downloadable release in `src/content.ts`, including both preview labels. Keep the exact GitHub asset URL and verify it exists before publishing. The website does not query GitHub on every visit.
- Main site copy is a typed English/Chinese object. Shared localized SEO metadata lives in `src/seo.ts`; the two routes select their language. Keep its origin, `public/sitemap.xml`, and `public/robots.txt` consistent when changing domains.
- `Brand.tsx` owns the hover, focus, click, Escape, and outside-dismiss story card. A short brand origin is also permanently visible below the product details.
- `Demo.tsx` owns the opt-in, cancelable sample playback. Changing scenarios clears the pending stage timer. Reduced-motion settings disable animation.
- The site fonts are bundled and served locally. No runtime third-party font request is made.
- App code, package identity, signing, and releases are unchanged by this website.

## Art direction

Warm ivory, ink black and pine green; contemporary editorial layout with restrained Chinese ink details. Original brand art was generated using the built-in image generation tool, not a stock image or an app screenshot. See [design/README.md](design/README.md) for prompts and source assets.

Production assets are `public/ink-landscape.webp`, `public/ziki-mark.png`, and `public/favicon.png`. Original PNGs in `design/` are not shipped. DM Sans and Instrument Serif are distributed by Fontsource under their respective SIL Open Font Licenses; copies are served in `public/licenses/`.
