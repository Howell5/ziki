import { APIError } from "better-auth/api";

type EmailEnv = Pick<Env, "DB" | "EMAIL" | "EMAIL_FROM" | "BETTER_AUTH_SECRET">;

/** Shared across instances and IPs. Prevents repeatedly mailing the same person.
 * Await delivery acceptance so a mail failure is never reported as a sent code.
 * No OTP, recipient or provider error text is written to application logs.
 */
export async function claimEmailSend(env: Pick<EmailEnv, "DB" | "BETTER_AUTH_SECRET">, email: string): Promise<void> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.BETTER_AUTH_SECRET),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`email-cooldown:${email.toLowerCase()}`));
  const recipient = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
  const now = Math.floor(Date.now() / 1000);
  const claim = await env.DB.prepare(`INSERT INTO email_cooldown (recipient,next_send_at) VALUES (?,?)
    ON CONFLICT(recipient) DO UPDATE SET next_send_at=excluded.next_send_at
    WHERE email_cooldown.next_send_at<=? RETURNING recipient`).bind(recipient, now + 60, now).first();
  if (!claim) throw new APIError("TOO_MANY_REQUESTS", { message: "Please wait before requesting another code." });
}

export async function sendLoginOTP(env: Pick<EmailEnv, "EMAIL" | "EMAIL_FROM">, email: string, otp: string): Promise<void> {
  try {
    await env.EMAIL.send({
      from: env.EMAIL_FROM, to: email, subject: "Your Ziki sign-in code",
      text: `Your Ziki sign-in code is ${otp}.\n\nIt expires in 5 minutes. Do not share this code.\nIf you did not request it, you can ignore this email.\n\nZiki — https://getziki.com`,
    });
  } catch {
    throw new APIError("SERVICE_UNAVAILABLE", { message: "Email delivery is unavailable. Please try again later." });
  }
}
