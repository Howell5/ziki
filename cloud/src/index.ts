import { createAuth } from "./auth";
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
      // Intentionally closed until identity provider, approval UI, and hosted pipeline pass staging.
      // Even changing the flag cannot turn an unfinished service into a public success path.
      throw new HttpError("cloud_not_configured", 503);
    } catch (error) {
      const known = error instanceof HttpError;
      return privateResponse(Response.json({ error: known ? error.code : "internal_error" }, { status: known ? error.status : 500 }));
    }
  },
} satisfies ExportedHandler<Env>;

/** Ready for staging wiring, NOT reachable from the public handler until P2 configuration/QA.
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
  return privateResponse(await createAuth(env).handler(await boundedRequest(request, 16_384)));
}
