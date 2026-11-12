import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import { Ledger } from "../src/ledger";

it("shortens atomically, replays at zero balance and never claims twice", async () => {
  const ledger = new Ledger(env.DB), user = crypto.randomUUID();
  await ledger.grant({ userId: user, source: crypto.randomUUID(), kind: "topup", seconds: 7, startsAt: 100, expiresAt: 1000 });
  const rows = await Promise.all(Array.from({ length: 8 }, () => ledger.reserveUpTo(user,"same",300,100)));
  expect(new Set(rows.map(row => row.id)).size).toBe(1);
  expect(rows[0]!.reserved_seconds).toBe(7);
  expect(await ledger.balance(user,100)).toBe(0);
  expect((await ledger.reserveUpTo(user,"same",300,100)).id).toBe(rows[0]!.id);
  expect((await Promise.all(Array.from({ length: 8 }, () => ledger.start(user,rows[0]!.id,101)))).filter(Boolean)).toHaveLength(1);
  await ledger.release(user,rows[0]!.id,"cancelled",102);
  expect(await ledger.balance(user,102)).toBe(7);
  expect(await ledger.start(user,rows[0]!.id,103)).toBe(false);
});

it("finds the maximum duration covered by grant expiry and refuses exhausted grants", async () => {
  const ledger = new Ledger(env.DB), user = crypto.randomUUID();
  await ledger.grant({ userId: user, source: crypto.randomUUID(), kind: "topup", seconds: 300, startsAt: 100, expiresAt: 225 });
  expect((await ledger.reserveUpTo(user,"deadline",300,100)).reserved_seconds).toBe(5);
  await expect(ledger.reserveUpTo(user,"other",300,100)).rejects.toMatchObject({ code: "unavailable" });
  await ledger.expire(user,225);
  await expect(ledger.reserveUpTo(user,"expired",300,225)).rejects.toMatchObject({ code: "unavailable" });
});
