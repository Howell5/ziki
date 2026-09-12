# Ziki Cloud — local foundation

This is **not a launched subscription service**. Public business/auth routes deliberately return `503 cloud_not_configured`; `/health` reports database reachability, not product readiness. No model key, fake login, payment, audio storage, or grant-creation endpoint is exposed.

## Local development

Requires Node 24. From this directory:

```sh
npm ci
npm run types
npm run check
npm test
npm run migrate:local
npm run dev
```

`npm run build` is a Workers dry run, **not a deployment**. The zero database UUID is local-only. Do not deploy this config or create a production database from it. A separate staging config and credentials are required after the external decisions in [the execution plan](../docs/cloud-mvp-plan.md).

Secrets belong in ignored `.dev.vars` locally and Workers secrets remotely. `BETTER_AUTH_SECRET` must be independently generated, at least 32 characters; never reuse a personal provider Key. Its absence is expected at this stage. Auth tests inject non-production fixtures without enabling public login.

## What is implemented

- D1 grants with source uniqueness, validity periods and revocation; per-grant reservation allocations and append-only-by-application usage events.
- Atomic reserve/allocation and conditional terminal transitions. One active dictation per user; one provider start claim; repeated settlement cannot charge twice.
- Server-only accounting API. `settle` accepts measured audio duration from future provider orchestration, never client-reported seconds. No endpoint calls it yet.
- Better Auth 1.7.4 D1 schema, session/bearer/device authorization configuration, revocation and ownership checks. Real identity-provider sign-in and browser approval UI are **not implemented/configured**.
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

Before public exposure, choose/configure the identity and model providers, complete the explicit device approval UI, add bounded hosted processing and actual runtime abuse controls, then pass authorized staging tests. Before charging, complete Stripe test-mode verification and approve prices, refund/partial-success rules and legal/licensing boundaries. Local fixtures do not satisfy those gates.
