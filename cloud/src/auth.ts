import { betterAuth, type BetterAuthOptions } from "better-auth";
import { bearer, deviceAuthorization } from "better-auth/plugins";

// One app, one auth authority. No invented JWT/password/refresh-token protocol.
// Database is a D1 binding in Workers; the broader type also permits offline schema generation.
export function authOptions(database: BetterAuthOptions["database"], origin: string, secret: string) {
  const url = new URL(origin);
  if (url.origin !== origin || url.username || url.password ||
      (url.protocol !== "https:" && !(url.protocol === "http:" && url.hostname === "127.0.0.1"))) {
    throw new Error("invalid_auth_origin");
  }
  if (!secret || secret.length < 32) throw new Error("auth_secret_not_configured");
  return {
    appName: "Ziki",
    baseURL: origin,
    basePath: "/api/auth",
    secret,
    database,
    trustedOrigins: [origin],
    emailAndPassword: { enabled: false },
    // Provider credentials are deliberately not guessed or copied from BYOK.
    socialProviders: {},
    session: { expiresIn: 60 * 60 * 24 * 7, updateAge: 60 * 60 * 24, cookieCache: { enabled: false } },
    account: { accountLinking: { enabled: false } },
    rateLimit: { enabled: true, storage: "database", window: 60, max: 60 },
    advanced: {
      useSecureCookies: url.protocol === "https:",
      ipAddress: { ipAddressHeaders: ["cf-connecting-ip"] },
    },
    // Library errors may contain request/provider material. Expose only application error classes.
    logger: { disabled: true },
    plugins: [bearer(), deviceAuthorization({
      expiresIn: "5m", interval: "5s", verificationUri: `${origin}/device`,
      validateClient: (clientId) => clientId === "ziki-macos",
    })],
  } satisfies BetterAuthOptions;
}

export function createAuth(env: Pick<Env, "DB" | "AUTH_ORIGIN" | "BETTER_AUTH_SECRET">) {
  // Request scoped: never share pending D1 I/O across Workers requests.
  return betterAuth(authOptions(env.DB, env.AUTH_ORIGIN, env.BETTER_AUTH_SECRET));
}
