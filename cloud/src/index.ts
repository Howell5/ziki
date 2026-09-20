import { createAuth, loginCapabilities } from "./auth";
import { accountPage } from "./account-page";
import { Ledger } from "./ledger";
import { boundedRequest, HttpError, privateResponse } from "./http";

export default {
  async fetch(request, env): Promise<Response> {
    try {
      const path = new URL(request.url).pathname;
      if (request.method === "GET" && path === "/health") {
        await env.DB.prepare("SELECT 1").first();
        return privateResponse(Response.json({ service: "ziki-cloud", environment: env.ENVIRONMENT, cloudEnabled: false }));
      }
      const enabled = String(env.AUTH_ENABLED) === "true" && Boolean(env.BETTER_AUTH_SECRET?.length >= 32);
      const capabilities = loginCapabilities(env);
      if (request.method === "GET" && (path === "/account" || path === "/device")) {
        return privateResponse(accountPage({ ...capabilities, enabled, device: path === "/device" }));
      }
      if (enabled) {
        // Only the canonical authority may receive session-bearing requests.
        if (new URL(request.url).origin !== env.AUTH_ORIGIN) throw new HttpError("origin_not_allowed", 403);
        if (path.startsWith("/api/auth/")) return await authHandler(request, env);
        if (path === "/v1/me") return await authenticatedAccount(request, env);
      }
      // Identity can be tested independently; no flag exposes unvalidated speech or billing.
      throw new HttpError("cloud_not_configured", 503);
    } catch (error) {
      const known = error instanceof HttpError;
      return privateResponse(Response.json({ error: known ? error.code : "internal_error" }, { status: known ? error.status : 500 }));
    }
  },
} satisfies ExportedHandler<Env>;

/** Reachable only when AUTH_ENABLED is explicitly configured.
 * Identity always comes from Better Auth; user IDs in headers/query/body are ignored.
 */
export async function authenticatedAccount(request: Request, env: Env): Promise<Response> {
  const auth = createAuth(env);
  const origin = request.headers.get("origin");
  if (origin && origin !== env.AUTH_ORIGIN) throw new HttpError("origin_not_allowed", 403);
  const session = await auth.api.getSession({ headers: request.headers });
  if (!session?.user.emailVerified) throw new HttpError("unauthorized", 401);
  if (request.method !== "GET" || new URL(request.url).pathname !== "/v1/me") throw new HttpError("not_found", 404);
  const seconds = await new Ledger(env.DB).balance(session.user.id, Math.floor(Date.now() / 1000));
  return privateResponse(Response.json({ user: { id: session.user.id, email: session.user.email }, availableSeconds: seconds }));
}

export async function authHandler(request: Request, env: Env): Promise<Response> {
  const origin = request.headers.get("origin");
  // Bearer requests are not cookie-CSRF, but we still reject explicit foreign browser origins.
  if (origin && origin !== env.AUTH_ORIGIN) return privateResponse(Response.json({ error: "origin_not_allowed" }, { status: 403 }));
  const path = new URL(request.url).pathname.slice("/api/auth".length);
  const native = path === "/device/code" || path === "/device/token";
  const callback = path === "/callback/google";
  const get = path === "/device" || callback;
  const post = native || path === "/sign-in/social" || path === "/sign-in/email-otp" ||
    path === "/email-otp/send-verification-otp" || path === "/sign-out" ||
    path === "/device/approve" || path === "/device/deny" || callback;
  if (!((request.method === "GET" && get) || (request.method === "POST" && post))) {
    throw new HttpError("not_found", 404);
  }
  // Device polling is native, callbacks use OAuth state. All other mutations are same-origin browser UI.
  if (request.method === "POST" && !native && !callback && origin !== env.AUTH_ORIGIN) {
    throw new HttpError("origin_not_allowed", 403);
  }
  const auth = createAuth(env);
  if (path === "/device" || path === "/device/approve" || path === "/device/deny") {
    const session = await auth.api.getSession({ headers: request.headers });
    if (!session?.user.emailVerified) throw new HttpError("unauthorized", 401);
  }
  const bounded = await boundedRequest(request, 16_384);
  if (path === "/sign-in/email-otp" || path === "/email-otp/send-verification-otp") {
    if (!loginCapabilities(env).email) throw new HttpError("email_not_configured", 503);
    if (path === "/email-otp/send-verification-otp") {
      const body = await bounded.clone().json<{ type?: string }>().catch(() => null);
      if (body?.type !== "sign-in") throw new HttpError("invalid_request", 400);
    }
  }
  const response = privateResponse(await auth.handler(bounded));
  // Browser sessions use HttpOnly cookies; the only bearer-token delivery path is device/token.
  response.headers.delete("set-auth-token");
  if (path === "/sign-in/email-otp" && response.ok) {
    const result = await response.json<{ user: unknown }>();
    response.headers.delete("content-length");
    return privateResponse(Response.json({ user: result.user }, { status: response.status, headers: response.headers }));
  }
  return response;
}
