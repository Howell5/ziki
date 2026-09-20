import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { loginCapabilities } from "../src/auth";
import { claimEmailSend } from "../src/email";

const origin = "http://127.0.0.1:8787";
let fixtureNumber = 10;
function fixture() {
  const sent: EmailMessageBuilder[] = [];
  const email = `${crypto.randomUUID()}@example.invalid`;
  const ip = `192.0.2.${fixtureNumber++}`;
  const config = {
    ...env, AUTH_ENABLED: "true", EMAIL_LOGIN_ENABLED: "true",
    BETTER_AUTH_SECRET: "local-login-fixture-not-for-deployment-9Hj2",
    EMAIL: { async send(message: EmailMessageBuilder) { sent.push(message); return { messageId: "local-fixture" }; } },
  } as unknown as Env;
  const call = (path: string, body?: object, headers: HeadersInit = {}) => worker.fetch(new Request(`${origin}${path}`, {
    method: body ? "POST" : "GET",
    headers: { "Content-Type": "application/json", Origin: origin, "cf-connecting-ip": ip, ...headers },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), config);
  const send = () => call("/api/auth/email-otp/send-verification-otp", { email, type: "sign-in" });
  const otp = () => sent.at(-1)!.text!.match(/\b\d{8}\b/)![0];
  const signIn = (code = otp()) => call("/api/auth/sign-in/email-otp", { email, otp: code });
  return { config, sent, email, call, send, otp, signIn };
}

describe("configured identity routes, local provider fixtures only", () => {
  it("keeps unconfigured login unavailable and speech/billing closed even with auth enabled", async () => {
    const f = fixture();
    expect(loginCapabilities(env)).toEqual({ google: false, email: false });
    for (const path of ["/v1/dictations", "/v1/billing/checkout"]) expect((await f.call(path, {})).status).toBe(503);
    const page = await worker.fetch(new Request(`${origin}/account`), env);
    expect(page.status).toBe(200);
    expect(page.headers.get("cache-control")).toBe("no-store");
    expect((await f.call("/api/auth/sign-up/email", { email: f.email, password: "not-supported" })).status).toBe(404);
    expect((await f.call("/api/auth/email-otp/send-verification-otp", { email: f.email, type: "forget-password" })).status).toBe(400);
    expect(f.sent).toHaveLength(0);
  });

  it("signs in with a hashed single-use OTP, exposes only a cookie session, and signs out", async () => {
    const f = fixture();
    expect((await f.send()).status).toBe(200);
    const code = f.otp();
    const rows = await env.DB.prepare('SELECT value FROM verification WHERE identifier=?').bind(`sign-in-otp-${f.email}`).all<{ value: string }>();
    expect(rows.results.length).toBeGreaterThan(0);
    expect(rows.results.some(row => row.value.includes(code))).toBe(false);
    const response = await f.signIn();
    expect(response.status).toBe(200);
    const body = await response.json<{ token?: string; user: { emailVerified: boolean } }>();
    expect(body.token).toBeUndefined();
    expect(body.user.emailVerified).toBe(true);
    expect(response.headers.get("set-auth-token")).toBeNull();
    const cookies = response.headers.getSetCookie();
    expect(cookies.some(cookie => cookie.includes("HttpOnly"))).toBe(true);
    const cookie = cookies.map(value => value.split(";")[0]).join("; ");
    expect((await f.call("/v1/me", undefined, { Cookie: cookie })).status).toBe(200);
    expect((await f.signIn(code)).ok).toBe(false);
    expect((await f.call("/api/auth/sign-out", {}, { Cookie: cookie })).ok).toBe(true);
    expect((await f.call("/v1/me", undefined, { Cookie: cookie })).status).toBe(401);
  });

  it("throttles resend without invalidating the already delivered code", async () => {
    const f = fixture();
    expect((await f.send()).ok).toBe(true);
    const code = f.otp();
    expect((await f.send()).status).toBe(429);
    expect(f.sent).toHaveLength(1);
    expect((await f.signIn(code)).ok).toBe(true);
  });

  it("claims one recipient send atomically across concurrent requests without retaining the address", async () => {
    const f = fixture();
    const results = await Promise.allSettled(Array.from({ length: 10 }, () => claimEmailSend(f.config, f.email)));
    expect(results.filter(result => result.status === "fulfilled")).toHaveLength(1);
    const rows = await env.DB.prepare("SELECT recipient FROM email_cooldown").all<{ recipient: string }>();
    expect(rows.results.every(row => /^[a-f0-9]{64}$/.test(row.recipient))).toBe(true);
  });

  it("rejects expired and repeatedly incorrect codes", async () => {
    const expired = fixture();
    await expired.send();
    const code = expired.otp();
    await env.DB.prepare('UPDATE verification SET expiresAt=? WHERE identifier=?').bind(Date.now() - 1000, `sign-in-otp-${expired.email}`).run();
    expect((await expired.signIn(code)).ok).toBe(false);
    const attempts = fixture();
    await attempts.send();
    const correct = attempts.otp();
    const wrong = correct === "00000000" ? "11111111" : "00000000";
    for (let index = 0; index < 3; index++) expect((await attempts.signIn(wrong)).ok).toBe(false);
    // A different IP bypasses the per-IP limiter, but not the OTP attempt budget.
    expect((await attempts.call("/api/auth/sign-in/email-otp", { email: attempts.email, otp: correct },
      { "cf-connecting-ip": "2001:db8::ffff" })).ok).toBe(false);
  });

  it("allows one session when the same OTP is submitted concurrently", async () => {
    const f = fixture();
    await f.send();
    const code = f.otp();
    const responses = await Promise.all([f.signIn(code), f.signIn(code)]);
    expect(responses.filter(response => response.ok)).toHaveLength(1);
  });

  it("does not report a sent code or expose provider details on email failure", async () => {
    const f = fixture();
    f.config.EMAIL = { async send() { throw new Error("private-provider-detail-and-recipient"); } };
    const response = await f.send();
    expect(response.status).toBe(503);
    expect(await response.text()).not.toContain("private-provider-detail");
  });

  it("creates Google OAuth state redirects locally and refuses external return URLs", async () => {
    const f = fixture();
    Object.assign(f.config, { GOOGLE_CLIENT_ID: "local-google-client", GOOGLE_CLIENT_SECRET: "local-google-secret" });
    const provider = "google";
    const response = await f.call("/api/auth/sign-in/social", { provider, callbackURL: "/device" });
    expect(response.ok).toBe(true);
    const { url } = await response.json<{ url: string }>();
    const redirect = new URL(url);
    expect(redirect.protocol).toBe("https:");
    expect(redirect.hostname).toBe("accounts.google.com");
    expect(redirect.searchParams.get("state")).toBeTruthy();
    expect(redirect.searchParams.get("redirect_uri")).toBe(`${origin}/api/auth/callback/${provider}`);
    expect((await f.call("/api/auth/sign-in/social", { provider, callbackURL: "https://evil.example/" })).ok).toBe(false);
  });

  it("rejects retired Discord sign-in and callbacks even with legacy credentials", async () => {
    const f = fixture();
    Object.assign(f.config, { DISCORD_CLIENT_ID: "legacy-client", DISCORD_CLIENT_SECRET: "legacy-secret" });
    expect(loginCapabilities(f.config)).toEqual({ google: false, email: true });
    const response = await f.call("/api/auth/sign-in/social", { provider: "discord", callbackURL: "/device" });
    expect(response.status).toBe(404);
    expect(response.headers.get("location")).toBeNull();
    expect(await response.json()).toMatchObject({ code: "PROVIDER_NOT_FOUND" });
    for (const body of [undefined, { code: "unused", state: "unused" }]) {
      expect((await f.call("/api/auth/callback/discord", body)).status).toBe(404);
    }
  });

  it("rejects wrong-host and missing/foreign-origin browser mutations", async () => {
    const f = fixture();
    for (const headers of [{}, { Origin: "https://evil.example" }] as Record<string, string>[]) {
      const response = await worker.fetch(new Request(`${origin}/api/auth/sign-in/email-otp`, {
        method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify({ email: f.email, otp: "12345678" }),
      }), f.config);
      expect(response.status).toBe(403);
    }
    expect((await worker.fetch(new Request("https://wrong.example/v1/me"), f.config)).status).toBe(403);
    expect((await f.call("/api/auth/device/approve", { userCode: "ABCD1234" })).status).toBe(401);
  });

  it("does not let an unverified social identity bind or approve a device", async () => {
    const f = fixture();
    const user = crypto.randomUUID();
    const token = crypto.randomUUID();
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare('INSERT INTO "user" (id,name,email,emailVerified,createdAt,updatedAt) VALUES (?,?,?,?,?,?)')
        .bind(user, "Unverified fixture", f.email, 0, now, now),
      env.DB.prepare('INSERT INTO "session" (id,token,userId,expiresAt,createdAt,updatedAt) VALUES (?,?,?,?,?,?)')
        .bind(crypto.randomUUID(), token, user, now + 600_000, now, now),
    ]);
    const headers = { Authorization: `Bearer ${token}` };
    expect((await f.call("/api/auth/device?user_code=TESTCODE", undefined, headers)).status).toBe(401);
    expect((await f.call("/api/auth/device/approve", { userCode: "TESTCODE" }, headers)).status).toBe(401);
  });
});
