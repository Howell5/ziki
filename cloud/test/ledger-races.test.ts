import { env } from "cloudflare:workers";
import { expect, it } from "vitest";
import { Ledger } from "../src/ledger";

async function fixture(seconds = 60) {
  const ledger = new Ledger(env.DB);
  const user = crypto.randomUUID();
  await ledger.grant({ userId:user, source:crypto.randomUUID(), kind:"trial", seconds, startsAt:0, expiresAt:10_000 });
  return { ledger, user };
}

it("atomic insufficient-funds checks survive repeated concurrent reserve/settle cycles", async () => {
  const { ledger, user } = await fixture(9);
  for (let round=0; round<3; round++) {
    const reservations = await Promise.all(Array.from({length:10},()=>ledger.reserve(user,`round-${round}`,3,100)));
    expect(new Set(reservations.map(r=>r.id)).size).toBe(1);
    const id = reservations[0]!.id;
    await ledger.start(user,id,101);
    await Promise.all(Array.from({length:10},()=>ledger.settle(user,id,3,102)));
  }
  expect(await ledger.balance(user,103)).toBe(0);
  await expect(ledger.reserve(user,"overdraw",1,104)).rejects.toMatchObject({code:"unavailable"});
  const total = await env.DB.prepare("SELECT SUM(seconds) AS total FROM usage_ledger WHERE user_id=?").bind(user).first<{total:number}>();
  expect(total?.total).toBe(9);
});

it("cancel vs settle race has one terminal outcome and balances match it", async () => {
  const { ledger, user } = await fixture();
  const r = await ledger.reserve(user,"race",30,100);
  await ledger.start(user,r.id,101);
  await Promise.allSettled([ledger.release(user,r.id,"cancelled",102),ledger.settle(user,r.id,20,102)]);
  const final = await ledger.get(user,r.id);
  expect(["cancelled","completed"]).toContain(final.status);
  const total = await env.DB.prepare("SELECT COALESCE(SUM(seconds),0) AS total FROM usage_ledger WHERE user_id=?").bind(user).first<{total:number}>();
  expect(total?.total).toBe(final.status === "completed" ? 20 : 0);
  expect(await ledger.balance(user,103)).toBe(final.status === "completed" ? 40 : 60);
});

it("expiry wins over a completion arriving at the exact deadline, without consuming replacement credits", async () => {
  const { ledger, user } = await fixture();
  const r = await ledger.reserve(user,"old",30,100);
  await ledger.start(user,r.id,101);
  await Promise.allSettled([ledger.expire(user,r.expires_at),ledger.settle(user,r.id,20,r.expires_at)]);
  expect((await ledger.get(user,r.id)).status).toBe("expired");
  const replacement = await ledger.reserve(user,"new",60,r.expires_at);
  expect(replacement.reserved_seconds).toBe(60);
  await expect(ledger.settle(user,r.id,20,r.expires_at+1)).rejects.toMatchObject({code:"invalid_state"});
  expect(await ledger.balance(user,r.expires_at+1)).toBe(0);
});
