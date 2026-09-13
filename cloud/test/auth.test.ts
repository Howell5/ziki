import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { getMigrations } from "better-auth/db/migration";
import { authOptions, createAuth } from "../src/auth";
import worker, { authenticatedAccount, authHandler } from "../src/index";
import { boundedRequest } from "../src/http";
import { Ledger } from "../src/ledger";

const origin = "http://127.0.0.1:8787";
// Local fixtures only. No public fake login endpoint and no personal secrets.
const testEnv = () => ({ ...env, BETTER_AUTH_SECRET: "local-auth-test-fixture-not-for-deployment-7K9v" });

async function identity(verified = true) {
  const user = crypto.randomUUID();
  const token = crypto.randomUUID();
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare('INSERT INTO "user" (id,name,email,emailVerified,createdAt,updatedAt) VALUES (?,?,?,?,?,?)')
      .bind(user,"Fixture",`${user}@example.invalid`,verified ? 1 : 0,now,now),
    env.DB.prepare('INSERT INTO "session" (id,token,userId,expiresAt,createdAt,updatedAt) VALUES (?,?,?,?,?,?)')
      .bind(crypto.randomUUID(),token,user,now+600_000,now,now),
  ]);
  return { user, token, headers: { Authorization: `Bearer ${token}` } };
}

describe("Better Auth on local D1 (not a live identity-provider test)", () => {
  it("has no auth schema drift", async () => {
    const migration = await getMigrations(authOptions(env.DB, origin, testEnv().BETTER_AUTH_SECRET));
    expect(migration.toBeCreated).toEqual([]);
    expect(migration.toBeAdded).toEqual([]);
    expect(migration.toBeAddedIndexes).toEqual([]);
    expect(migration.schemaProblems).toEqual([]);
  });

  it("rejects missing credentials, unsafe origins, and public spoofed identities", async () => {
    expect(() => authOptions(env.DB, origin, "")).toThrow("auth_secret_not_configured");
    expect(() => authOptions(env.DB, "http://public.example", testEnv().BETTER_AUTH_SECRET)).toThrow("invalid_auth_origin");
    const response = await worker.fetch(new Request(`${origin}/v1/me?user_id=somebody`, { headers: { "X-User-Id": "somebody" } }), testEnv());
    expect(response.status).toBe(503);
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("reads only the verified session owner's balance, ignoring caller user IDs", async () => {
    const current = await identity();
    const other = await identity();
    const now = Math.floor(Date.now()/1000);
    const ledger = new Ledger(env.DB);
    await ledger.grant({ userId: current.user, source: crypto.randomUUID(), kind: "trial", seconds: 45, startsAt: now, expiresAt: now+3600 });
    await ledger.grant({ userId: other.user, source: crypto.randomUUID(), kind: "trial", seconds: 90, startsAt: now, expiresAt: now+3600 });
    const response = await authenticatedAccount(new Request(`${origin}/v1/me?user_id=${other.user}`, { headers: current.headers }), testEnv());
    expect(await response.json()).toMatchObject({ user: { id: current.user }, availableSeconds: 45 });
  });

  it("rejects anonymous, unverified, expired and revoked sessions", async () => {
    const current = await identity();
    const unverified = await identity(false);
    const request = (headers: HeadersInit = {}) => new Request(`${origin}/v1/me`, { headers });
    await expect(authenticatedAccount(request(),testEnv())).rejects.toMatchObject({ status: 401 });
    await expect(authenticatedAccount(request(unverified.headers),testEnv())).rejects.toMatchObject({ status: 401 });
    await env.DB.prepare('UPDATE "session" SET expiresAt=? WHERE token=?').bind(Date.now()-1000,current.token).run();
    await expect(authenticatedAccount(request(current.headers),testEnv())).rejects.toMatchObject({ status: 401 });
    const revoked = await identity();
    const response = await authHandler(new Request(`${origin}/api/auth/sign-out`, {
      method: "POST", headers: { ...revoked.headers, Origin: origin, "Content-Type": "application/json" }, body: "{}",
    }),testEnv());
    expect(response.ok).toBe(true);
    await expect(authenticatedAccount(request(revoked.headers),testEnv())).rejects.toMatchObject({ status: 401 });
  });

  it("enforces browser Origin and rejects oversized streamed auth bodies", async () => {
    const current = await identity();
    await expect(authenticatedAccount(new Request(`${origin}/v1/me`, { headers: { ...current.headers, Origin: "https://evil.example" } }),testEnv()))
      .rejects.toMatchObject({ status: 403 });
    const response = await authHandler(new Request(`${origin}/api/auth/sign-out`, {
      method: "POST", headers: { ...current.headers, Origin: "https://evil.example", "Content-Type": "application/json" }, body: "{}",
    }),testEnv());
    expect(response.status).toBe(403);
    const body = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array(17_000)); controller.close(); } });
    await expect(boundedRequest(new Request(`${origin}/api/auth/device/code`, { method: "POST", body }),16_384)).rejects.toMatchObject({ status: 413 });
  });

  it("binds device codes to Ziki and requires approval before token issuance", async () => {
    const auth = createAuth(testEnv());
    const headers = { "Content-Type": "application/json", "cf-connecting-ip": "192.0.2.1" };
    const post = (path: string, body: object) => auth.handler(new Request(`${origin}/api/auth${path}`, { method: "POST", headers, body: JSON.stringify(body) }));
    const invalid = await post("/device/code",{ client_id: "other-app" });
    expect(invalid.ok).toBe(false);
    const response = await post("/device/code",{ client_id: "ziki-macos" });
    expect(response.ok).toBe(true);
    const code = await response.json<{ device_code: string; user_code: string }>();
    expect(code.device_code.length).toBeGreaterThan(20);
    const token = await post("/device/token", { client_id: "ziki-macos", device_code: code.device_code, grant_type: "urn:ietf:params:oauth:grant-type:device_code" });
    expect(await token.json()).toMatchObject({ error: "authorization_pending" });
    const approve = await post("/device/approve",{ userCode: code.user_code });
    expect(approve.ok).toBe(false);
  });

  it("redeems an explicitly approved device code only once and only for its bound user", async () => {
    const auth = createAuth(testEnv());
    const current = await identity();
    const other = await identity();
    const request = (path: string, body: object, authorization?: string) => auth.handler(new Request(`${origin}/api/auth${path}`, {
      method: "POST", headers: { "Content-Type": "application/json", Origin: origin, ...(authorization ? { Authorization: authorization } : {}) }, body: JSON.stringify(body),
    }));
    const codeResponse = await request("/device/code",{ client_id: "ziki-macos" });
    const code = await codeResponse.json<{ device_code: string; user_code: string }>();
    const review = await auth.handler(new Request(`${origin}/api/auth/device?user_code=${code.user_code}`, { headers: current.headers }));
    expect(review.ok).toBe(true);
    const foreignApproval = await request("/device/approve",{ userCode: code.user_code },other.headers.Authorization);
    expect(foreignApproval.status).toBe(403);
    expect((await request("/device/approve",{ userCode: code.user_code },current.headers.Authorization)).ok).toBe(true);
    const body = { client_id: "ziki-macos", device_code: code.device_code, grant_type: "urn:ietf:params:oauth:grant-type:device_code" };
    const responses = await Promise.all([request("/device/token",body),request("/device/token",body)]);
    const success = responses.filter(response => response.ok);
    expect(success).toHaveLength(1);
    const token = await success[0]!.json<{ access_token: string }>();
    const session = await auth.api.getSession({ headers: new Headers({ Authorization: `Bearer ${token.access_token}` }) });
    expect(session?.user.id).toBe(current.user);
  });
});
