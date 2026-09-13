import { betterAuth, type BetterAuthOptions } from "better-auth";
import { bearer, deviceAuthorization, emailOTP } from "better-auth/plugins";
import { APIError, createAuthMiddleware } from "better-auth/api";
import { claimEmailSend, sendLoginOTP } from "./email";

type LoginOptions = {
  google?: { clientId: string; clientSecret: string };
  discord?: { clientId: string; clientSecret: string };
  sendOTP?: (email: string, otp: string) => Promise<void>;
  claimOTP?: (email: string) => Promise<void>;
};

type AuthEnv = Pick<Env, "DB" | "AUTH_ORIGIN" | "BETTER_AUTH_SECRET"> & Partial<Pick<Env,
  "GOOGLE_CLIENT_ID" | "GOOGLE_CLIENT_SECRET" | "DISCORD_CLIENT_ID" | "DISCORD_CLIENT_SECRET" |
  "EMAIL_LOGIN_ENABLED" | "EMAIL" | "EMAIL_FROM">>;

export function loginCapabilities(env: AuthEnv) {
  return {
    google: Boolean(env.GOOGLE_CLIENT_ID?.trim() && env.GOOGLE_CLIENT_SECRET?.trim()),
    discord: Boolean(env.DISCORD_CLIENT_ID?.trim() && env.DISCORD_CLIENT_SECRET?.trim()),
    email: String(env.EMAIL_LOGIN_ENABLED) === "true" && Boolean(env.EMAIL && env.EMAIL_FROM?.trim()),
  };
}

// One app, one auth authority. No invented JWT/password/refresh-token protocol.
// Database is a D1 binding in Workers; the broader type also permits offline schema generation.
export function authOptions(database: BetterAuthOptions["database"], origin: string, secret: string, login: LoginOptions = {}) {
  const url = new URL(origin);
  if (url.origin !== origin || url.username || url.password ||
      (url.protocol !== "https:" && !(url.protocol === "http:" && url.hostname === "127.0.0.1"))) {
    throw new Error("invalid_auth_origin");
  }
  if (!secret || secret.length < 32) throw new Error("auth_secret_not_configured");
  // Better Auth intentionally absorbs background mail errors. Track only the
  // failed Request identity so an after hook can return an honest UI status.
  // Weak, factory-local state: no recipient/OTP retention or cross-request flag.
  const failedDeliveries = new WeakSet<Request>();
  return {
    appName: "Ziki",
    baseURL: origin,
    basePath: "/api/auth",
    secret,
    database,
    trustedOrigins: [origin],
    onAPIError: { errorURL: `${origin}/account` },
    emailAndPassword: { enabled: false },
    // Provider credentials are deliberately not guessed or copied from BYOK.
    socialProviders: { ...(login.google ? { google: login.google } : {}), ...(login.discord ? { discord: login.discord } : {}) },
    session: { expiresIn: 60 * 60 * 24 * 7, updateAge: 60 * 60 * 24, cookieCache: { enabled: false } },
    account: { accountLinking: { enabled: false } },
    rateLimit: { enabled: true, storage: "database", window: 60, max: 60 },
    advanced: {
      useSecureCookies: url.protocol === "https:",
      ipAddress: { ipAddressHeaders: ["cf-connecting-ip"] },
    },
    // Library errors may contain request/provider material. Expose only application error classes.
    logger: { disabled: true },
    hooks: { before: createAuthMiddleware(async (ctx) => {
      if (ctx.path !== "/email-otp/send-verification-otp") return;
      const email = ctx.body?.email;
      if (ctx.body?.type !== "sign-in" || !login.sendOTP) throw new APIError("SERVICE_UNAVAILABLE", { message: "Email sign-in is not configured." });
      // Reserve before the plugin rotates the OTP, so a throttled resend cannot invalidate it.
      if (typeof email === "string" && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        await login.claimOTP?.(email.toLowerCase());
      }
    }), after: createAuthMiddleware(async (ctx) => {
      if (ctx.request && failedDeliveries.has(ctx.request)) {
        failedDeliveries.delete(ctx.request);
        throw new APIError("SERVICE_UNAVAILABLE", { message: "Email delivery is unavailable. Please try again later." });
      }
    }) },
    plugins: [bearer(), deviceAuthorization({
      expiresIn: "5m", interval: "5s", verificationUri: `${origin}/device`,
      validateClient: (clientId) => clientId === "ziki-macos",
    }), emailOTP({
      otpLength: 8, expiresIn: 300, allowedAttempts: 3, storeOTP: "hashed",
      rateLimit: { window: 60, max: 3 },
      async sendVerificationOTP({ email, otp, type }, ctx) {
        if (type !== "sign-in" || !login.sendOTP) throw new APIError("SERVICE_UNAVAILABLE", { message: "Email sign-in is not configured." });
        try { await login.sendOTP(email, otp); }
        catch (error) {
          if (ctx?.request) failedDeliveries.add(ctx.request);
          else throw error;
        }
      },
    })],
  } satisfies BetterAuthOptions;
}

export function createAuth(env: AuthEnv) {
  // Request scoped: never share pending D1 I/O across Workers requests.
  const capabilities = loginCapabilities(env);
  return betterAuth(authOptions(env.DB, env.AUTH_ORIGIN, env.BETTER_AUTH_SECRET, {
    ...(capabilities.google ? { google: { clientId: env.GOOGLE_CLIENT_ID!, clientSecret: env.GOOGLE_CLIENT_SECRET! } } : {}),
    ...(capabilities.discord ? { discord: { clientId: env.DISCORD_CLIENT_ID!, clientSecret: env.DISCORD_CLIENT_SECRET! } } : {}),
    ...(capabilities.email ? {
      claimOTP: (email: string) => claimEmailSend(env, email),
      sendOTP: (email: string, otp: string) => sendLoginOTP({ EMAIL: env.EMAIL!, EMAIL_FROM: env.EMAIL_FROM! }, email, otp),
    } : {}),
  }));
}
