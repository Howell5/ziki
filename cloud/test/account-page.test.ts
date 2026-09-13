import { describe, expect, it } from "vitest";
import { accountPage } from "../src/account-page";

async function markup(options: Parameters<typeof accountPage>[0]): Promise<{ html: string; response: Response }> {
  const response = accountPage(options);
  return { response, html: await response.text() };
}

describe("bounded Ziki account HTML", () => {
  it("returns a nonce-protected, same-origin-only document without external resources", async () => {
    const { response, html } = await markup({ google: true, discord: true, email: true, enabled: true, device: false });
    const policy = response.headers.get("content-security-policy") || "";
    const nonceMatch = policy.match(/script-src 'nonce-([0-9a-f]+)'/);

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(policy).toContain("default-src 'none'");
    expect(policy).toContain("connect-src 'self'");
    expect(policy).toContain("form-action 'self'");
    expect(policy).toContain("frame-ancestors 'none'");
    expect(html).toContain('<meta name="robots" content="noindex, nofollow, noarchive" />');
    expect(nonceMatch).not.toBeNull();
    expect(html).toContain(`nonce="${nonceMatch?.[1]}"`);
    expect(html).not.toMatch(/<(?:link|img|script)[^>]+(?:https?:|src=)/i);
    expect(html).not.toContain("localStorage");
    expect(html).not.toContain("sessionStorage");
    expect(html).not.toContain("innerHTML");
    expect(html).not.toContain("location.search");
  });

  it("renders configured social and email flows with the correct callback", async () => {
    const { html } = await markup({ google: true, discord: false, email: true, enabled: true, device: false });

    expect(html).toContain('data-provider="google"');
    expect(html).toContain("Discord");
    expect(html).toContain("Unavailable");
    expect(html).toContain("/api/auth/sign-in/social");
    expect(html).toContain('JSON.stringify({ provider, callbackURL })');
    expect(html).toContain('const callbackURL = isDevicePage ? "/device" : "/account";');
    expect(html).toContain("/api/auth/email-otp/send-verification-otp");
    expect(html).toContain('type: "sign-in"');
    expect(html).toContain("/api/auth/sign-in/email-otp");
    expect(html).toContain('maxlength="8"');
    expect(html).toContain("8-digit code");
    expect(html).toContain('searchParams.has("error")');
    expect(html).toContain("Sign-in failed. Check the provider and try again.");
    expect(html).not.toContain("error_description");
    expect(html).toContain('target.origin === window.location.origin || target.protocol === "https:"');
    expect(html).toContain("/v1/me");
    expect(html).toContain("/api/auth/sign-out");
    expect(html).toContain("Hosted dictation is not available yet.");
    expect(html).toContain("BYOK works without a Ziki login.");
  });

  it("keeps the disabled state honest and does not expose login controls", async () => {
    const { html } = await markup({ google: true, discord: true, email: true, enabled: false, device: false });

    expect(html).toContain("Cloud account is not available yet.");
    expect(html).toContain("Hosted dictation is still not available.");
    expect(html).toContain("no login is required for BYOK");
    expect(html).not.toContain('data-provider="google"');
    expect(html).not.toContain('<form data-email-form');
  });

  it("requires explicit device-code review before approval or denial", async () => {
    const { html } = await markup({ google: true, discord: true, email: false, enabled: true, device: true });

    expect(html).toContain('id="device-user-code"');
    expect(html).toContain('name="user_code"');
    expect(html).toContain("Reviewing a code never approves it.");
    expect(html).toContain("Only approve a code shown in Ziki on your own Mac.");
    expect(html).toContain("只批准你自己 Mac 上 Ziki 显示的代码。");
    expect(html).toContain("/api/auth/device?user_code=");
    expect(html).toContain("/api/auth/device/approve");
    expect(html).toContain("/api/auth/device/deny");
    expect(html).toContain('review.user_code !== userCode || review.client_id !== "ziki-macos" || review.status !== "pending"');
    expect(html).toContain("reviewedCodeNode.textContent = review.user_code");
    expect(html).toContain('data-device-approve disabled');
    expect(html).toContain('data-device-deny disabled');
    expect(html).toContain("reviewedCode = review.user_code");
    expect(html).toContain("Please sign in first, then review this Mac code.");
    expect(html).toContain("if (!reviewedCode || !button || button.disabled) return;");
    expect(html).toContain("reviewRequestId += 1");
    expect(html).toContain("if (requestId !== reviewRequestId) return;");
    expect(html).toContain('codeInput.addEventListener("input", () => resetReview());');
    expect(html).toContain('JSON.stringify({ userCode: reviewedCode })');
    expect(html).not.toContain("URLSearchParams");
  });

  it("supports changing email, cooldown-gated resend, and a clean second sign-in", async () => {
    const { html } = await markup({ google: false, discord: false, email: true, enabled: true, device: false });

    expect(html).toContain('data-change-email');
    expect(html).toContain('data-resend-otp disabled');
    expect(html).toContain("resendRemaining = 60");
    expect(html).toContain("window.setTimeout(tick, 1000)");
    expect(html).toContain("emailForm.reset()");
    expect(html).toContain("otpForm.reset()");
    expect(html).toContain("await loadSession()");
    expect(html).toContain('signedInSession = false');
    expect(html).toContain("stopResendCooldown()");
    expect(html).toContain("resetReview(true)");
    expect(html).toContain("验证码已发送，请查看收件箱。");
    expect(html).toContain("网络错误。请检查连接，然后重试。");
  });

  it("uses DOM textContent for returned account and device values", async () => {
    const { html } = await markup({ google: false, discord: false, email: true, enabled: true, device: true });

    expect(html).toContain("emailNode.textContent = user.email");
    expect(html).toContain("idNode.textContent = user.id");
    expect(html).toContain("clientNode.textContent");
    expect(html).toContain("scopeNode.textContent");
    expect(html).toContain("node.textContent = message");
    expect(html).not.toContain("insertAdjacentHTML");
    expect(html).not.toContain("document.write");
  });
});
