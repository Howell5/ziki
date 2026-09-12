# Website verification — 2026-09-12

Tested the production `dist/client/` output using a plain Python static server and Ego Browser, not the Vite development server.

## Automated checks

- `npm run build`: two prerendered pages, `/` and `/zh`.
- `npm run check`: TypeScript passed.
- `npm test`: five checks passed: locale structure parity, official version-pinned download URL, list/prose separation, and complete prerendered HTML and local assets in each language.
- `npm install`: zero reported dependency vulnerabilities at installation time.

## Browser checks

- English desktop at 1440 × 1000; Chinese mobile at 390 × 844. Full-page visual review completed.
- Both languages at 320px: document scroll width equals viewport width; no horizontal scrolling. The decorative closing mark extends within an intentionally clipped container.
- No broken images observed on the English narrow-screen page.
- Brand card opens on hover, stays open while moving into its content, and closes on Escape.
- Keyboard focus opens the card; Tab reaches its close button. Escape returns focus to the brand button without leaving the card open.
- Clicking the brand pins the card; clicking outside dismisses it.
- Mobile card at 390px remains inside the viewport and can be closed by its visible button.
- Demo advances through Listening → Thinking → Ready. Scenario switching resets playback; the second scenario renders a paragraph, not a list, in both languages.
- Explicit stop returns the demo to its initial state. No actual microphone, provider, or clipboard operation is performed.
- With `prefers-reduced-motion: reduce` emulated on the current document, waveform and status animations both compute to `none`.
- FAQ expands on activation; localized navigation changes document title and HTML language.
- No error/warning events observed in the captured browser events during the final interaction round.

The actual desktop app and its permissions were not exercised; they were not changed. The download URL was checked against the existing GitHub v0.5.0 release asset list, without downloading or installing the app.

## Production deployment — 2026-09-12

The following checks extend the initial local verification above:

- Deployed to Cloudflare Workers Static Assets as `ziki-website` with custom domains and valid HTTPS.
- `https://getziki.com/` and `/zh/` return HTTP 200 and prerendered localized HTML.
- HTTP and `www` requests return HTTP 301 to the HTTPS apex, preserving path and query parameters.
- `robots.txt`, `sitemap.xml`, and `social-card.jpg` return HTTP 200 with appropriate content types; an unknown path returns HTTP 404.
- Live Chinese mobile page at 390 × 844 has no horizontal overflow or broken images; document language, title, and canonical match the Chinese route.
- Live English story card opens on hover and closes on Escape. The illustrative demo reaches Ready to use; language navigation reaches the Chinese page.
- Build, TypeScript, and six automated tests pass, including canonical/hreflang/share metadata and crawl/static-host configuration. Wrangler dry-run and initial deployment both succeeded.
- Cloudflare Workers Builds is connected to `main` for `website/**` changes. Automatic deployment verification is reported separately after pushing the production configuration commit.

No desktop package was built, installed, or released. Search Console submission and indexing have not been verified.
