import { env } from "cloudflare:workers";
import { applyD1Migrations } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { Ledger, LedgerError } from "../src/ledger";

const NOW = 1_000;
const FAR_FUTURE = 10_000;
const TEST_RUN = crypto.randomUUID();

function user(label: string) {
  return `ledger-${TEST_RUN}-${label}`;
}

function ledger() {
  return new Ledger(env.DB);
}

function source(label: string) {
  return `${label}-${crypto.randomUUID()}`;
}

async function addGrant(
  userId: string,
  seconds: number,
  options: { source?: string; startsAt?: number; expiresAt?: number } = {},
) {
  const grant = ledger();
  await grant.grant({
    userId,
    source: options.source ?? source("grant"),
    kind: "trial",
    seconds,
    startsAt: options.startsAt ?? 0,
    expiresAt: options.expiresAt ?? FAR_FUTURE,
  });
}

async function allocationsFor(dictationId: string) {
  const result = await env.DB.prepare(
    "SELECT grant_id, seconds, position FROM allocations WHERE dictation_id=? ORDER BY position",
  )
    .bind(dictationId)
    .all<{ grant_id: string; seconds: number; position: number }>();
  return result.results;
}

async function usageFor(dictationId: string) {
  const result = await env.DB.prepare(
    `SELECT l.grant_id, l.seconds FROM usage_ledger l
      JOIN allocations a ON a.dictation_id=l.dictation_id AND a.grant_id=l.grant_id
      WHERE l.dictation_id=? ORDER BY a.position`,
  )
    .bind(dictationId)
    .all<{ grant_id: string; seconds: number }>();
  return result.results;
}

async function expectLedgerError(promise: Promise<unknown>, code: LedgerError["code"]) {
  await expect(promise).rejects.toMatchObject({ code });
}

beforeEach(async () => {
  const pattern = `ledger-${TEST_RUN}-%`;
  await env.DB.batch([
    env.DB.prepare("DELETE FROM usage_ledger WHERE user_id LIKE ?").bind(pattern),
    env.DB.prepare("DELETE FROM allocations WHERE user_id LIKE ?").bind(pattern),
    env.DB.prepare("DELETE FROM dictations WHERE user_id LIKE ?").bind(pattern),
    env.DB.prepare("DELETE FROM credit_grants WHERE user_id LIKE ?").bind(pattern),
  ]);
});

describe("Ledger grants", () => {
  it("is idempotent for the same grant and rejects conflicts, including cross-user reuse", async () => {
    const grant = ledger();
    const input = {
      userId: user("a"),
      source: source("purchase"),
      kind: "topup" as const,
      seconds: 60,
      startsAt: NOW,
      expiresAt: FAR_FUTURE,
    };

    await grant.grant(input);
    await grant.grant(input);
    await expectLedgerError(
      grant.grant({ ...input, seconds: 61 }),
      "idempotency_conflict",
    );
    await expectLedgerError(
      grant.grant({ ...input, userId: user("b") }),
      "idempotency_conflict",
    );

    const count = await env.DB.prepare("SELECT COUNT(*) AS count FROM credit_grants WHERE user_id=?")
      .bind(user("a"))
      .first<{ count: number }>();
    expect(count?.count).toBe(1);
  });

  it("excludes expired, revoked, and not-yet-valid grants from balance", async () => {
    const grant = ledger();
    const revokedSource = source("revoked");
    await grant.grant({
      userId: user("a"),
      source: source("expired"),
      kind: "trial",
      seconds: 10,
      startsAt: 0,
      expiresAt: NOW,
    });
    await grant.grant({
      userId: user("a"),
      source: source("future"),
      kind: "trial",
      seconds: 20,
      startsAt: NOW + 1,
      expiresAt: FAR_FUTURE,
    });
    await grant.grant({
      userId: user("a"),
      source: revokedSource,
      kind: "trial",
      seconds: 30,
      startsAt: 0,
      expiresAt: FAR_FUTURE,
    });
    await env.DB.prepare("UPDATE credit_grants SET revoked_at=? WHERE source=?")
      .bind(NOW, revokedSource)
      .run();

    expect(await grant.balance(user("a"), NOW)).toBe(0);
    expect(await grant.balance(user("a"), NOW + 1)).toBe(20);
  });
});

describe("Ledger reservations", () => {
  it("allocates across eligible grants in earliest-expiry order and refunds unused reservation on settle", async () => {
    const grant = ledger();
    const earlySource = source("early");
    const lateSource = source("late");
    await addGrant(user("a"), 5, { source: earlySource, expiresAt: 2_000 });
    await addGrant(user("a"), 10, { source: lateSource, expiresAt: 3_000 });

    const reservation = await grant.reserve(user("a"), "recording-1", 8, NOW);
    const allocations = await allocationsFor(reservation.id);
    expect(allocations).toHaveLength(2);
    expect(allocations[0]?.seconds).toBe(5);
    expect(allocations[1]?.seconds).toBe(3);
    expect(allocations[0]?.position).toBe(0);
    expect(allocations[1]?.position).toBe(5);
    expect(await grant.balance(user("a"), NOW)).toBe(7);

    await grant.start(user("a"), reservation.id, NOW + 1);
    const settled = await grant.settle(user("a"), reservation.id, 6, NOW + 2);
    expect(settled.status).toBe("completed");
    expect(settled.consumed_seconds).toBe(6);
    expect(await usageFor(reservation.id)).toEqual([
      { grant_id: allocations[0]?.grant_id, seconds: 5 },
      { grant_id: allocations[1]?.grant_id, seconds: 1 },
    ]);
    expect(await grant.balance(user("a"), NOW + 2)).toBe(9);
  });

  it("does not overdraw under 20 parallel reservations and replays the same key", async () => {
    const grant = ledger();
    await addGrant(user("a"), 30);

    const attempts = await Promise.all(
      Array.from({ length: 20 }, (_, index) =>
        grant.reserve(user("a"), `parallel-${index}`, 2, NOW),
      ).map(async (attempt) => {
        try {
          return { ok: true as const, value: await attempt };
        } catch (error) {
          return { ok: false as const, error };
        }
      }),
    );
    const successful = attempts.filter(
      (attempt): attempt is Extract<(typeof attempts)[number], { ok: true }> => attempt.ok,
    );
    expect(successful).toHaveLength(1);
    for (const attempt of attempts) {
      if (attempt.ok) continue;
      expect((attempt.error as LedgerError).code).toBe("unavailable");
    }

    const first = successful[0];
    if (!first) throw new Error("expected one successful reservation");
    const replay = await grant.reserve(user("a"), first.value.idempotency_key, 2, NOW);
    expect(replay.id).toBe(first.value.id);
    await expectLedgerError(
      grant.reserve(user("a"), first.value.idempotency_key, 3, NOW),
      "idempotency_conflict",
    );
    expect(await grant.balance(user("a"), NOW)).toBe(28);
  });

  it("rejects a reservation when a grant cannot survive its deadline", async () => {
    await addGrant(user("a"), 20, { expiresAt: NOW + 10 });
    await expectLedgerError(ledger().reserve(user("a"), "too-late", 1, NOW), "unavailable");
  });
});

describe("Ledger provider lifecycle", () => {
  it("allows exactly one provider start claim", async () => {
    await addGrant(user("a"), 10);
    const reservation = await ledger().reserve(user("a"), "claim-once", 2, NOW);
    const claims = await Promise.all([
      ledger().start(user("a"), reservation.id, NOW + 1),
      ledger().start(user("a"), reservation.id, NOW + 1),
    ]);
    expect(claims.filter(Boolean)).toHaveLength(1);
    expect((await ledger().get(user("a"), reservation.id)).status).toBe("processing");
  });

  it("makes settle idempotent for the same measurement and rejects a different replay", async () => {
    await addGrant(user("a"), 10);
    const grant = ledger();
    const reservation = await grant.reserve(user("a"), "settle-once", 5, NOW);
    await grant.start(user("a"), reservation.id, NOW + 1);

    const first = await grant.settle(user("a"), reservation.id, 3, NOW + 2);
    const same = await grant.settle(user("a"), reservation.id, 3, NOW + 3);
    expect(same).toMatchObject({ id: first.id, status: "completed", consumed_seconds: 3 });
    await expectLedgerError(
      grant.settle(user("a"), reservation.id, 4, NOW + 3),
      "idempotency_conflict",
    );
    expect(
      await env.DB.prepare("SELECT COUNT(*) AS count FROM usage_ledger WHERE dictation_id=?")
        .bind(reservation.id)
        .first<{ count: number }>(),
    ).toMatchObject({ count: 1 });
  });

  it("lets cancellation win over a delayed provider completion", async () => {
    await addGrant(user("a"), 10);
    const grant = ledger();
    const reservation = await grant.reserve(user("a"), "cancel-race", 2, NOW);
    await grant.start(user("a"), reservation.id, NOW + 1);
    await grant.release(user("a"), reservation.id, "cancelled", NOW + 2);

    expect((await grant.get(user("a"), reservation.id)).status).toBe("cancelled");
    await expectLedgerError(
      grant.settle(user("a"), reservation.id, 1, NOW + 3),
      "invalid_state",
    );
  });

  it("expires work before rejecting a delayed completion", async () => {
    await addGrant(user("a"), 10);
    const grant = ledger();
    const reservation = await grant.reserve(user("a"), "expiry-race", 1, NOW);
    await grant.start(user("a"), reservation.id, NOW + 1);
    await grant.expire(user("a"), reservation.expires_at);

    expect((await grant.get(user("a"), reservation.id)).status).toBe("expired");
    await expectLedgerError(
      grant.settle(user("a"), reservation.id, 1, reservation.expires_at + 1),
      "invalid_state",
    );
  });
});

describe("Ledger access and validation", () => {
  it("does not allow another user to read or mutate a dictation", async () => {
    await addGrant(user("a"), 10);
    const grant = ledger();
    const reservation = await grant.reserve(user("a"), "private", 2, NOW);

    await expectLedgerError(grant.get(user("b"), reservation.id), "not_found");
    expect(await grant.start(user("b"), reservation.id, NOW + 1)).toBe(false);
    await expectLedgerError(
      grant.settle(user("b"), reservation.id, 1, NOW + 2),
      "not_found",
    );
    await expectLedgerError(
      grant.release(user("b"), reservation.id, "cancelled", NOW + 2),
      "not_found",
    );
  });

  it("rejects invalid input bounds", async () => {
    const grant = ledger();
    await expectLedgerError(
      grant.grant({
        userId: user("a"),
        source: source("bad-seconds"),
        kind: "trial",
        seconds: 0,
        startsAt: 0,
        expiresAt: 1,
      }),
      "invalid_input",
    );
    await expectLedgerError(
      grant.grant({
        userId: user("a"),
        source: source("bad-window"),
        kind: "trial",
        seconds: 1,
        startsAt: 10,
        expiresAt: 10,
      }),
      "invalid_input",
    );
    await addGrant(user("a"), 10);
    await expectLedgerError(grant.reserve(user("a"), "zero", 0, NOW), "invalid_input");
    await expectLedgerError(grant.reserve(user("a"), "too-long", 301, NOW), "invalid_input");
    await expectLedgerError(grant.balance(user("a"), 1.5), "invalid_input");
    await expectLedgerError(grant.get("", "id"), "invalid_input");
    await expectLedgerError(grant.settle(user("a"), "id", 301, NOW), "invalid_input");
  });
});

describe("D1 runtime guarantees", () => {
  it("replays the migration set without changing the migration ledger", async () => {
    await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
    const migrationRows = await env.DB.prepare(
      "SELECT name FROM d1_migrations ORDER BY name",
    ).all<{ name: string }>();
    expect(migrationRows.results).toHaveLength(env.TEST_MIGRATIONS.length);
    expect(migrationRows.results.map((row) => row.name)).toEqual(
      env.TEST_MIGRATIONS.map((migration) => migration.name).sort(),
    );
    expect(
      await env.DB.prepare(
        "SELECT name FROM sqlite_master WHERE type='view' AND name='grant_balances'",
      ).first<{ name: string }>(),
    ).toMatchObject({ name: "grant_balances" });
  });

  it("rolls back every statement in a failed D1 batch", async () => {
    const firstSource = source("batch-first");
    await expect(
      env.DB.batch([
        env.DB.prepare(
          "INSERT INTO credit_grants (id,user_id,source,kind,seconds,starts_at,expires_at) VALUES (?,?,?,?,?,?,?)",
        ).bind(crypto.randomUUID(), user("a"), firstSource, "trial", 10, 0, FAR_FUTURE),
        env.DB.prepare(
          "INSERT INTO credit_grants (id,user_id,source,kind,seconds,starts_at,expires_at) VALUES (?,?,?,?,?,?,?)",
        ).bind(crypto.randomUUID(), user("a"), source("batch-invalid"), "trial", 0, 0, FAR_FUTURE),
      ]),
    ).rejects.toBeDefined();

    expect(
      await env.DB.prepare("SELECT COUNT(*) AS count FROM credit_grants WHERE source=?")
        .bind(firstSource)
        .first<{ count: number }>(),
    ).toMatchObject({ count: 0 });
  });
});
