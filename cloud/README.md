# Ziki Cloud — account foundation (not launched)

This is **not a launched subscription service**. `/account` and `/device` display configuration-aware account UI. Auth/account API routes remain closed unless `AUTH_ENABLED=true` and an independent auth secret is set; speech and billing remain hard-closed regardless of flags. `/health` reports database reachability, not product readiness. No model key, fake login, payment, audio storage, or grant-creation endpoint is exposed.

## Local development

### First-time configuration / 首次填写配置

Copy [`.env.example`](.env.example) to `cloud/.env` (from the repository root):

```sh
cd cloud
cp -n .env.example .env
chmod 600 .env
```

The template explains each value, where to obtain it, exact local OAuth callbacks, and which sections can stay empty. Start with an independently generated `BETTER_AUTH_SECRET`, Google credentials, and the reserved Bailian Singapore credentials. Stripe can wait until the payment stage. **Bailian, model-test budget and Stripe fields are handoff placeholders, not implemented runtime features yet.**

模板中的中文注释已列明获取位置和必填/可留空项。填完后通知维护者即可，不需粘贴密钥或自行部署。邮件没有额外 API Key，但真实发送仍须开通 Cloudflare 发信能力、验证域名；仅改环境变量不能完成这一步。

`.env` is Git-ignored. Do not create both `.env` and `.dev.vars`: Wrangler prefers `.dev.vars` when it exists; `.env.local` can also override `.env`. Use only `cloud/.env` for this handoff. These files are local configuration, not automatic production secret uploads. The empty committed template contains no usable credentials.

Requires Node 24. From this directory:

```sh
npm ci
npm run types
npm run check
npm test
npm run test:page-script
npm run migrate:local
npm run dev
```

`npm run build` is a Workers dry run, **not a deployment**. The zero database UUID is local-only. Do not deploy this config or create a production database from it. A separate staging config and credentials are required after the external decisions in [the execution plan](../docs/cloud-mvp-plan.md).

Secrets belong in ignored `.env` locally and Workers secrets remotely. `BETTER_AUTH_SECRET` must be independently generated, at least 32 characters; never reuse a personal provider Key. Tests disable dotenv loading and explicitly override auth settings with non-production fixtures, never public fake-login routes.

## Identity configuration

One public repository contains the client, website and service. BYOK never requires this service or an account. Code visibility does not expose provider credentials, production configuration or user data; the project license still needs to be chosen.

| Setting | Purpose |
|---|---|
| `AUTH_ENABLED` | Explicit opt-in for isolated identity validation, independent of speech/billing |
| `AUTH_ORIGIN` | Exact canonical HTTPS origin; local-only HTTP exception: `127.0.0.1` |
| `BETTER_AUTH_SECRET` | Independently generated Workers secret, at least 32 characters |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth ID (config) and secret (Workers secret) |
| `EMAIL_LOGIN_ENABLED` | Enable only after verifying Email Service availability and sender domain |
| `EMAIL_FROM` / `EMAIL` | Verified sender and native Cloudflare `send_email` binding |

The Google callback is `<AUTH_ORIGIN>/api/auth/callback/google`. Register the exact isolated staging URL before testing. Do not reuse production OAuth clients or D1 during development. The checked-in email binding restricts the sender to `login@getziki.com`; that is an intended address, **not evidence it is verified**. Local bindings do not prove real delivery. No login provider is enabled by placeholder credentials in the committed configuration.

| Google Web application setting | Local validation (current) | Planned hosted service (not deployed) |
|---|---|---|
| Authorized JavaScript origin | `http://127.0.0.1:8787` | `https://api.getziki.com` |
| Authorized redirect URI | `http://127.0.0.1:8787/api/auth/callback/google` | `https://api.getziki.com/api/auth/callback/google` |

The server-side OAuth flow requires the redirect URI, not merely the origin/domain. Keep local `AUTH_ORIGIN` unchanged until a separate hosted environment, DNS, TLS and D1 are ready. Entering a URL in Google does not deploy a backend. For a testing OAuth app, add the signing-in Google account to its test users. See [Google's web-server OAuth setup](https://developers.google.com/identity/protocols/oauth2/web-server).

Discord sign-in was removed on 2026-09-21. Any leftover `DISCORD_*` entries in a private local file are ignored and can be removed; no credential re-entry or database reset is needed.

The browser uses same-origin HttpOnly cookies. A Mac must obtain `/api/auth/device/code`, open `/device`, display the user code, and poll `/api/auth/device/token` using the server interval. The user enters/reviews the code and explicitly approves or denies it. Merely opening a link never approves a device. Native UI/token storage and real provider roundtrips are still pending P2 work.

## What is implemented

- D1 grants with source uniqueness, validity periods and revocation; per-grant reservation allocations and append-only-by-application usage events.
- Atomic reserve/allocation and conditional terminal transitions. One active dictation per user; one provider start claim; repeated settlement cannot charge twice.
- Server-only accounting API. `settle` accepts measured audio duration from future provider orchestration, never client-reported seconds. No endpoint calls it yet.
- Better Auth 1.7.4 D1 schema, conditional Google configuration, email OTP and device approval UI. Implemented adapters and local fixtures are **not live identity-provider verification**.
- Eight-digit, five-minute, hashed, single-use OTP with three attempts. Atomic per-recipient email cooldown precedes OTP rotation; failed sending returns an error without logging recipients/codes/provider payloads.
- Bounded auth bodies, no-store responses, explicit origin protection, no raw request/provider logging.

Ledger methods take Unix **seconds** supplied by the server clock; Better Auth manages its own timestamps. Reserve at most 300 seconds with a 120-second finishing allowance. Grants must remain valid through that deadline. These are conservative technical bounds, not approved commercial allowances. Grant identity/amount/window is immutable through this API; `source` is a server-owned globally unique event identity. Refunds, subscription reconciliation, deletion/retention and trial-abuse prevention still require P2–P4 work.

## Testing and dependency decisions

Tests run in workerd/Miniflare with local D1, not a JavaScript balance mock. The SQL auth migration was generated with Better Auth's migration API and checked for drift against D1.

`wrangler types --include-runtime false` generates only the small project binding declaration. Runtime types come from the pinned official `@cloudflare/workers-types` package, avoiding a 15,000-line generated runtime copy in repository diffs and agent context.

The newest installed Workers SDK at implementation time supports compatibility date `2026-09-11`, not `2026-09-13`. The test pool's older transitive Miniflare/Wrangler are aligned to the current SDK with explicit overrides. `sharp` is pinned to patched `0.35.4` to remove the transitive libheif advisory; this project does not process images. Review/remove overrides when the pool updates. `npm audit fix --force` is not used to downgrade the test framework.

Official references checked 2026-09-13:

- [D1 database and atomic batches](https://developers.cloudflare.com/d1/worker-api/d1-database/)
- [Workers best practices](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/)
- [Better Auth database support](https://better-auth.com/docs/concepts/database)
- [Device authorization and required approval UX](https://better-auth.com/docs/plugins/device-authorization)
- [Workers secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Google authentication](https://better-auth.com/docs/authentication/google)
- [Email OTP](https://better-auth.com/docs/plugins/email-otp)
- [Cloudflare Email Service Workers sending API](https://developers.cloudflare.com/email-service/api/send-emails/workers-api/)

Before public exposure, configure Google/email and independent Bailian Singapore credentials, complete native login and bounded hosted processing, verify edge/mail abuse controls and retention (including expired email cooldown rows), then pass authorized staging tests. Before charging, complete Stripe test-mode verification and approve prices, refund/partial-success rules and legal/licensing boundaries. Local fixtures do not satisfy those gates.
