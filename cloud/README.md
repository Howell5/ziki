# Ziki Cloud — account and bounded speech (not launched)

This is **not a launched subscription service**. `/account` and `/device` display configuration-aware account UI. Auth/account API routes remain closed unless `AUTH_ENABLED=true` and an independent auth secret is set; speech additionally requires `CLOUD_ENABLED=true`, `ENVIRONMENT=local|staging` and independent Bailian Beijing credentials. Production speech and all payment routes remain closed. `/health` reports database reachability, not product readiness. No model key, fake login, payment, audio storage, or grant-creation endpoint is exposed.

## Local development

### First-time configuration / 首次填写配置

Copy [`.env.example`](.env.example) to `cloud/.env` (from the repository root):

```sh
cd cloud
cp -n .env.example .env
chmod 600 .env
```

The template explains each value, where to obtain it, exact local OAuth callbacks, and which sections can stay empty. Start with an independently generated `BETTER_AUTH_SECRET`, Google credentials, and independent Bailian Beijing credentials. Stripe can wait until the payment stage. Bailian credentials now configure isolated speech processing; `CLOUD_ENABLED` stays false by default. Model-test budget is only a handoff record, not an enforced cost limit. Stripe remains unimplemented.

模板中的中文注释已列明获取位置和必填/可留空项。填完后通知维护者即可，不需粘贴密钥或自行部署。邮件没有额外 API Key，但真实发送仍须开通 Cloudflare 发信能力、验证域名；仅改环境变量不能完成这一步。

`.env` is Git-ignored. Do not create both `.env` and `.dev.vars`: Wrangler prefers `.dev.vars` when it exists; `.env.local` can also override `.env`. Use only `cloud/.env` for this handoff. These files are local configuration, not automatic production secret uploads. The empty committed template contains no usable credentials.

Requires Node 24. From this directory:

```sh
npm ci
npm run types
npm run check
npm test
npm run test:page-script
npm run test:proxy
npm run migrate:local
npm run dev
```

If Google is reachable only through your HTTP(S) proxy, use `npm run dev:proxy` instead of `npm run dev`. It uses the existing `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` environment variables with Node 24's proxy-aware HTTP transport; keep `127.0.0.1,localhost,::1` in `NO_PROXY`. It uses the same ignored credentials and local D1 state, binds only to loopback, and does not change deployed Workers. Ordinary outbound HTTP requests fail after 15 seconds rather than leaving OAuth callbacks pending. WebSocket upgrades retain Miniflare's direct connection behavior and require separate speech connectivity verification. The plain Wrangler CLI's proxy notice covers its Node requests, not workerd's outbound sockets.

If Google consent appears stuck, check the first callback request before refreshing: Better Auth consumes OAuth state before exchanging the code, so replaying that callback can report `state_mismatch` and hide the original network failure. Start a fresh sign-in after fixing connectivity; do not disable the state check.

`npm run test:proxy` uses a local fixture proxy and workerd to check POST forwarding, manual redirects, sanitized connection failures and direct WebSocket echo. It does not contact Google or load personal credentials.

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

The browser uses same-origin HttpOnly cookies. A Mac must obtain `/api/auth/device/code`, open `/device`, display the user code, and poll `/api/auth/device/token` using the server interval. The user enters/reviews the code and explicitly approves or denies it. Merely opening a link never approves a device. Native integration is maintained separately; real provider roundtrips are still required for staging acceptance.

## What is implemented

- D1 grants with source uniqueness, validity periods and revocation; per-grant reservation allocations and append-only-by-application usage events.
- Atomic reserve/allocation and conditional terminal transitions. One active dictation per user; one provider start claim; repeated settlement cannot charge twice.
- Server-only accounting API. `settle` accepts byte-measured duration from the speech stream, never client-reported seconds.
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

Before public exposure, configure Google/email and independent Bailian Beijing credentials, validate native login and bounded hosted processing, verify edge/mail abuse controls and retention (including expired email cooldown rows), then pass authorized staging tests. Before charging, complete Stripe test-mode verification and approve prices, refund/partial-success rules and legal/licensing boundaries. Local fixtures do not satisfy those gates.

## P2 speech contract (isolated local/staging only)

`BAILIAN_API_KEY` is a server-only secret; `BAILIAN_WORKSPACE_ID` is the matching Beijing workspace ID (ASCII alphanumeric/hyphen, at most 63 characters). Hosts and models are fixed, never supplied by requests. No dependencies, Durable Objects or audio storage were added. A separate staging Wrangler configuration is still needed; the committed config is local-only.

All speech routes require a Better Auth bearer session with verified email. Cookie-only requests, query parameters/tokens, explicit foreign Origins and other users' sessions are rejected. Auth remains separately gated. No grant, settle, payment, arbitrary proxy or public fixture endpoint exists.

- `POST /v1/dictations`: exactly `{idempotencyKey: UUID, maxSeconds: 1..300}`; reserve up to eligible balance and replay the original reservation. Returns `{id,maxSeconds,status}`.
- `GET /v1/dictations/:id`: only `{id,maxSeconds,status}`, never transcript data.
- `POST /v1/dictations/:id/cancel`: conditional terminal transition and release; idempotent.
- `GET /v1/dictations/:id/stream`: bearer WebSocket upgrade; only one atomic provider claim. Invalid upgrade releases an unclaimed reservation; a duplicate claim cannot interrupt the winning stream.

First message is exactly `{type:"start",language:"auto"|"zh"|"en",cleanupEnabled:boolean,context:[{rawTranscript,polishedTranscript}]}`. Context is at most three turns and 8,000 Unicode code points combined. Wait for `ready` before audio. Send 16 kHz mono PCM16 little-endian binary frames, nonempty, even-length and at most 32,000 bytes. Total must not exceed `maxSeconds*32000`; at the limit send `{type:"finish"}` to retain the result. Excess bytes fail the stream and release its reservation. No client duration is accepted. `{type:"cancel"}` and socket close stop upstream immediately.

Events are `ready`, `hypothesis`/`segmentFinal` (cumulative `text`), `completed` (`rawText,text,billedSeconds,cleanupFailed`) and `error` (finite `code` only). Completion is sent after conditional D1 settlement, at `ceil(receivedBytes/32000)` seconds; whitespace-only recognition costs zero. Cleanup runs once using Qwen3.5 Flash and the Swift conservative prompt, including its untrusted-context constraints. HTTP/format/empty/truncated/timeout cleanup failures return raw recognition. Text, context and audio are never persisted or logged.

Bounds: client start 10s, provider start/finish 30s each, recording reserved duration + 10s, entire session reservation expiry (duration + 120s), cleanup 15s with a 20s stage guard. Client JSON <=32 KiB, provider JSON <=64 KiB, combined pending application messages <=256 KiB / 64 messages; cumulative transcript <=64,000 UTF-16 units and sentence IDs 0..4095. Strict state/format violations terminate the stream. Binary frame limits apply after runtime delivery: Workers buffers an incoming frame before the handler can validate it. See [Workers WebSocket binary delivery](https://developers.cloudflare.com/workers/runtime-apis/websockets/).

An active stream polls D1 after each 1s delay; reads have a 2s deadline and fail closed. Thus remote REST cancellation has bounded polling/read latency, as approved in the architecture contract. Conditional settlement prevents charging when cancellation wins before settlement. A same-socket cancellation/close stops transport synchronously; release is retained with `waitUntil`. If D1 itself is unavailable, release cannot be guaranteed immediately; reservation expiry remains the durable fallback, reclaimed by the next balance/reserve/query operation.

Tests use real workerd WebSocketPairs and D1 with a fixture fetch transport and controllable timers. D1 read-failure tests wrap only the failing read; accounting still uses real D1. They cover auth/origin/ownership, short-balance replay, concurrent claims, PCM bounds, queue bounds, cancellation and settlement races, state-read failures/deadlines, provider phases/errors, cleanup fallbacks and billing. Passing fixtures does not verify live provider schema, credentials, model quality, edge delivery latency or a physically separate deployed isolate. No real provider calls are authorized by tests or this README.
