export type AccountPageOptions = {
  google: boolean;
  email: boolean;
  enabled: boolean;
  device: boolean;
};

function nonce(): string {
  const bytes = new Uint8Array(18);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function escapeAttribute(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function copy(en: string, zh: string): string {
  return `data-en="${escapeAttribute(en)}" data-zh="${escapeAttribute(zh)}"`;
}

function providerButton(enabled: boolean): string {
  const label = "Google";
  const zh = "Google";
  if (!enabled) {
    return `<button class="provider-button unavailable" type="button" disabled aria-disabled="true">
      <span>${label}</span><span class="button-note" ${copy("Unavailable", "暂不可用")}>Unavailable</span>
    </button>`;
  }
  return `<button class="provider-button" type="button" data-provider="google">
    <span class="provider-mark" aria-hidden="true">G</span>
    <span ${copy(`Continue with ${label}`, `使用 ${zh} 继续`)}>Continue with ${label}</span>
  </button>`;
}

function authPanel(options: AccountPageOptions): string {
  if (!options.enabled) {
    return `<section class="auth-panel unavailable-panel" aria-labelledby="account-status-title">
      <p class="section-kicker" ${copy("ACCOUNT ACCESS", "账户访问")}>ACCOUNT ACCESS</p>
      <h2 id="account-status-title" ${copy("Cloud account is not available yet.", "云端账户暂不可用。")}>Cloud account is not available yet.</h2>
      <p class="muted" ${copy("Hosted dictation is still not available. You can keep using Ziki with your own provider key; no login is required for BYOK.", "托管听写尚不可用。你可以继续使用自己的服务商密钥；BYOK 无需登录。")}>Hosted dictation is still not available. You can keep using Ziki with your own provider key; no login is required for BYOK.</p>
    </section>`;
  }

  const social = providerButton(options.google);
  const email = options.email
    ? `<div class="email-flow">
        <div class="rule"><span ${copy("or use email", "或使用邮箱")}>or use email</span></div>
        <form data-email-form novalidate>
          <label for="account-email" ${copy("Email address", "邮箱地址")}>Email address</label>
          <div class="input-row">
            <input id="account-email" name="email" type="email" inputmode="email" autocomplete="email" required placeholder="you@example.com" />
            <button class="text-button" type="submit" ${copy("Send code", "发送验证码")}>Send code</button>
          </div>
        </form>
        <form data-otp-form hidden novalidate>
          <label for="account-otp" ${copy("Verification code", "验证码")}>Verification code</label>
          <div class="input-row">
            <input id="account-otp" name="otp" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="8" pattern="[0-9]{8}" required placeholder="8-digit code" />
            <button class="text-button" type="submit" ${copy("Sign in", "登录")}>Sign in</button>
          </div>
          <p class="hint" data-otp-hint ${copy("Check your inbox for the code.", "请查看收件箱中的验证码。")}>Check your inbox for the code.</p>
          <div class="otp-tools">
            <button class="inline-button" type="button" data-change-email ${copy("Change email", "更换邮箱")}>Change email</button>
            <button class="inline-button" type="button" data-resend-otp disabled><span data-resend-label ${copy("Resend code", "重新发送验证码")}>Resend code</span><span data-resend-countdown aria-live="polite"></span></button>
          </div>
        </form>
      </div>`
    : `<p class="hint" ${copy("Email sign-in is not configured.", "邮箱登录尚未配置。")}>Email sign-in is not configured.</p>`;

  return `<section class="auth-panel" aria-label="Ziki account">
    <div data-auth-signed-out>
      <p class="section-kicker" ${copy("ACCOUNT ACCESS", "账户访问")}>ACCOUNT ACCESS</p>
      <h2 id="sign-in-title" ${copy("Sign in to Ziki.", "登录 Ziki。")}>Sign in to Ziki.</h2>
      <p class="muted" ${copy("Use your account when hosted dictation is ready, or to approve a Mac device.", "托管听写上线后可使用账户，也可以用账户批准 Mac 设备。")}>Use your account when hosted dictation is ready, or to approve a Mac device.</p>
      <div class="social-stack">${social}</div>
      ${email}
      <p class="status" data-auth-status role="status" aria-live="polite"></p>
    </div>
    <div data-auth-signed-in hidden>
      <p class="section-kicker" ${copy("SIGNED IN", "已登录")}>SIGNED IN</p>
      <h2 ${copy("Your Ziki account.", "你的 Ziki 账户。")}>Your Ziki account.</h2>
      <dl class="account-facts">
        <div><dt ${copy("Email", "邮箱")}>Email</dt><dd data-user-email>—</dd></div>
        <div><dt ${copy("Account ID", "账户 ID")}>Account ID</dt><dd data-user-id>—</dd></div>
        <div><dt ${copy("Available time", "可用时长")}>Available time</dt><dd><span data-available-seconds>—</span> <span ${copy("seconds", "秒")}>seconds</span></dd></div>
      </dl>
      <button class="quiet-button" type="button" data-sign-out ${copy("Sign out", "退出登录")}>Sign out</button>
      <p class="status" data-auth-status role="status" aria-live="polite"></p>
    </div>
  </section>`;
}

function devicePanel(): string {
  return `<section class="device-panel" aria-labelledby="device-title">
    <p class="section-kicker" ${copy("MAC CONNECTION", "Mac 连接")}>MAC CONNECTION</p>
    <h2 id="device-title" ${copy("Approve a device.", "批准设备。")}>Approve a device.</h2>
    <p class="muted" ${copy("Enter the short code shown by Ziki on your own Mac. Reviewing a code never approves it.", "输入 Ziki 在你自己的 Mac 上显示的短码。查看代码不会自动批准。")}>Enter the short code shown by Ziki on your own Mac. Reviewing a code never approves it.</p>
    <form data-device-review-form novalidate>
      <label for="device-user-code" ${copy("Code from your Mac", "Mac 上的代码")}>Code from your Mac</label>
      <div class="code-row">
        <input id="device-user-code" name="user_code" type="text" inputmode="latin" autocomplete="one-time-code" spellcheck="false" maxlength="32" required placeholder="ABCD-EFGH" />
        <button class="text-button" type="submit" ${copy("Review code", "查看代码")}>Review code</button>
      </div>
    </form>
    <div class="review-card" data-device-review hidden aria-live="polite">
      <div class="review-heading"><span class="review-dot" aria-hidden="true"></span><span ${copy("Code found", "已找到代码")}>Code found</span></div>
      <dl class="review-facts">
        <div><dt ${copy("Code", "代码")}>Code</dt><dd data-device-code>—</dd></div>
        <div><dt ${copy("App", "应用")}>App</dt><dd data-device-client>—</dd></div>
        <div><dt ${copy("Requested access", "请求权限")}>Requested access</dt><dd data-device-scope>—</dd></div>
      </dl>
      <p class="warning"><strong ${copy("Take a moment.", "请确认。")}>Take a moment.</strong> <span ${copy("Only approve a code shown in Ziki on your own Mac.", "只批准你自己 Mac 上 Ziki 显示的代码。")}>Only approve a code shown in Ziki on your own Mac.</span></p>
      <div class="approval-actions">
        <button class="approve-button" type="button" data-device-approve disabled ${copy("Approve on this Mac", "批准这台 Mac")}>Approve on this Mac</button>
        <button class="quiet-button" type="button" data-device-deny disabled ${copy("Deny", "拒绝")}>Deny</button>
      </div>
    </div>
    <p class="status" data-device-status role="status" aria-live="polite"></p>
  </section>`;
}

function pageMarkup(options: AccountPageOptions, pageNonce: string): string {
  const device = options.device;
  const title = device ? "Connect your Mac to Ziki." : "Your Ziki account.";
  const description = device
    ? "A calm, explicit handoff between your Mac and your Ziki account."
    : "A small, secure home for your Ziki account.";
  const zhTitle = device ? "将你的 Mac 连接到 Ziki。" : "你的 Ziki 账户。";
  const zhDescription = device ? "在你的 Mac 与 Ziki 账户之间进行清晰、明确的连接。" : "你的 Ziki 账户，一个小而安全的归处。";

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#f5f0e8" />
    <meta name="robots" content="noindex, nofollow, noarchive" />
    <title>Ziki · ${title}</title>
    <style nonce="${pageNonce}">
      :root {
        color-scheme: light;
        --ivory: #f5f0e8;
        --paper: #fbf8f2;
        --ink: #1d2624;
        --muted: #6c736d;
        --line: #d9d3c8;
        --soft-line: #e8e2d8;
        --coral: #b94f3b;
        --coral-dark: #943d2c;
        --shadow: 0 24px 70px rgba(46, 47, 39, .09);
        --radius: 18px;
      }
      * { box-sizing: border-box; }
      html { min-width: 320px; background: var(--ivory); }
      body { margin: 0; min-height: 100vh; color: var(--ink); background: var(--ivory); font-family: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif; }
      button, input { font: inherit; }
      button { cursor: pointer; }
      button:disabled { cursor: not-allowed; }
      :focus-visible { outline: 3px solid rgba(228, 108, 79, .5); outline-offset: 3px; }
      a { color: inherit; }
      .page-shell { width: min(1120px, calc(100% - 40px)); margin: 0 auto; }
      .topbar { display: flex; align-items: center; justify-content: space-between; min-height: 90px; border-bottom: 1px solid var(--line); }
      .brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 18px; font-weight: 700; letter-spacing: -.04em; }
      .top-nav { display: flex; align-items: center; gap: 22px; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 13px; }
      .top-nav a { color: var(--muted); text-decoration: none; }
      .top-nav a:hover { color: var(--ink); }
      .language-button { padding: 6px 0; color: var(--muted); background: transparent; border: 0; font-size: 12px; }
      .language-button:hover { color: var(--ink); }
      main { padding: 72px 0 96px; }
      .hero { max-width: 670px; margin-bottom: 50px; }
      .eyebrow, .section-kicker { margin: 0 0 14px; color: var(--coral-dark); font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 11px; font-weight: 800; letter-spacing: .15em; }
      h1, h2, p { margin-top: 0; }
      h1 { max-width: 650px; margin-bottom: 18px; font-size: clamp(42px, 7vw, 76px); font-weight: 400; letter-spacing: -.065em; line-height: .98; }
      h2 { margin-bottom: 12px; font-size: 31px; font-weight: 400; letter-spacing: -.045em; line-height: 1.04; }
      .hero-copy { max-width: 500px; margin: 0; color: var(--muted); font-size: 19px; line-height: 1.45; }
      .content-grid { display: grid; grid-template-columns: minmax(0, 1.07fr) minmax(280px, .68fr); gap: 22px; align-items: start; }
      .auth-panel, .device-panel, .info-panel { padding: 34px; background: var(--paper); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); }
      .auth-panel { min-height: 390px; }
      .device-panel { min-height: 390px; box-shadow: none; }
      .info-panel { display: grid; gap: 24px; background: transparent; border-color: var(--soft-line); box-shadow: none; }
      .info-block + .info-block { padding-top: 24px; border-top: 1px solid var(--line); }
      .info-title { margin-bottom: 8px; font-size: 21px; letter-spacing: -.03em; }
      .muted, .hint { color: var(--muted); line-height: 1.5; }
      .muted { max-width: 440px; margin-bottom: 25px; font-size: 15px; }
      .hint { margin: 12px 0 0; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 12px; }
      .otp-tools { display: flex; justify-content: space-between; gap: 14px; margin-top: 16px; }
      .inline-button { padding: 0; color: var(--muted); background: transparent; border: 0; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 11px; text-align: left; }
      .inline-button:hover:not(:disabled) { color: var(--ink); }
      .inline-button:disabled { color: #aaa89f; }
      .social-stack { display: grid; gap: 10px; }
      .provider-button { display: flex; align-items: center; justify-content: center; gap: 10px; width: 100%; min-height: 48px; color: var(--paper); background: var(--ink); border: 1px solid var(--ink); border-radius: 9px; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 13px; font-weight: 700; transition: background .18s ease, transform .18s ease; }
      .provider-button:hover:not(:disabled) { background: #35413d; transform: translateY(-1px); }
      .provider-button.unavailable { justify-content: space-between; padding: 0 15px; color: var(--muted); background: transparent; border-color: var(--line); }
      .provider-mark { display: inline-grid; width: 20px; height: 20px; place-items: center; color: var(--ink); background: var(--paper); border-radius: 50%; font-size: 12px; }
      .button-note { font-size: 11px; font-weight: 500; }
      .rule { display: flex; align-items: center; gap: 12px; margin: 25px 0 20px; color: var(--muted); font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 11px; }
      .rule::before, .rule::after { height: 1px; flex: 1; content: ""; background: var(--soft-line); }
      label { display: block; margin-bottom: 8px; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 12px; font-weight: 700; }
      .input-row, .code-row { display: flex; gap: 9px; }
      input { width: 100%; min-width: 0; height: 46px; padding: 0 13px; color: var(--ink); background: #fffdf9; border: 1px solid var(--line); border-radius: 8px; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 14px; }
      input::placeholder { color: #aaa89f; }
      input:focus { border-color: var(--coral); outline: 0; }
      .text-button, .approve-button, .quiet-button { min-height: 46px; padding: 0 17px; border-radius: 8px; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 12px; font-weight: 800; white-space: nowrap; }
      .text-button { color: var(--paper); background: var(--coral); border: 1px solid var(--coral); }
      .text-button:hover { background: var(--coral-dark); border-color: var(--coral-dark); }
      .approve-button { color: var(--paper); background: var(--coral); border: 1px solid var(--coral); }
      .approve-button:disabled { color: #a5a49e; background: #e9e4db; border-color: #e9e4db; }
      .quiet-button { color: var(--ink); background: transparent; border: 1px solid var(--line); }
      .quiet-button:hover:not(:disabled) { border-color: var(--ink); }
      .quiet-button:disabled { color: #aaa89f; }
      .status { min-height: 18px; margin: 18px 0 0; color: var(--coral-dark); font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 12px; line-height: 1.45; }
      .account-facts, .review-facts { display: grid; gap: 0; margin: 28px 0; }
      .account-facts > div, .review-facts > div { display: flex; justify-content: space-between; gap: 18px; padding: 13px 0; border-top: 1px solid var(--soft-line); }
      dt { color: var(--muted); font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 11px; }
      dd { max-width: 65%; margin: 0; overflow-wrap: anywhere; text-align: right; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 12px; font-weight: 700; }
      .review-card { margin-top: 25px; padding: 20px; background: #f6f0e6; border: 1px solid #e0d8ca; border-radius: 12px; }
      .review-heading { display: flex; align-items: center; gap: 8px; margin-bottom: 2px; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 12px; font-weight: 800; }
      .review-dot { width: 8px; height: 8px; background: #6b9a71; border-radius: 50%; }
      .warning { margin: 21px 0; color: #6a4a35; font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 12px; line-height: 1.5; }
      .warning strong { color: var(--ink); }
      .approval-actions { display: flex; flex-wrap: wrap; gap: 9px; }
      .unavailable-panel { min-height: 0; }
      .unavailable-panel h2 { max-width: 340px; }
      footer { padding: 22px 0 30px; border-top: 1px solid var(--line); color: var(--muted); font-family: "DM Sans", "Avenir Next", sans-serif; font-size: 11px; }
      [hidden] { display: none !important; }
      @media (max-width: 760px) {
        .page-shell { width: min(100% - 28px, 620px); }
        .topbar { min-height: 72px; }
        .top-nav { gap: 14px; }
        .top-nav a { font-size: 12px; }
        main { padding: 52px 0 70px; }
        .hero { margin-bottom: 36px; }
        h1 { font-size: clamp(42px, 13vw, 62px); }
        .hero-copy { font-size: 17px; }
        .content-grid { grid-template-columns: 1fr; }
        html:not([data-signed-in]) .auth-panel { order: -1; }
        .auth-panel, .device-panel, .info-panel { padding: 25px 21px; }
      }
      @media (max-width: 460px) {
        .brand { font-size: 16px; }
        .top-nav a { display: none; }
        .input-row, .code-row { display: grid; grid-template-columns: 1fr; }
        .text-button { width: 100%; }
        .otp-tools { align-items: flex-start; flex-direction: column; }
        .approval-actions > * { flex: 1; }
        dd { max-width: 58%; }
      }
      @media (prefers-reduced-motion: reduce) {
        *, *::before, *::after { scroll-behavior: auto !important; transition-duration: .01ms !important; }
      }
    </style>
  </head>
  <body>
    <div class="page-shell">
      <header class="topbar">
        <a class="brand" href="/account" aria-label="Ziki account">
          <span>Ziki</span>
        </a>
        <nav class="top-nav" aria-label="Account navigation">
          ${device ? `<a href="/account" ${copy("Account", "账户")}>Account</a>` : `<a href="/device" ${copy("Connect a Mac", "连接 Mac")}>Connect a Mac</a>`}
          <button class="language-button" type="button" data-language-toggle aria-label="切换到中文">中文</button>
        </nav>
      </header>
      <main>
        <section class="hero">
          <p class="eyebrow" ${copy(device ? "DEVICE HANDOFF" : "ACCOUNT", device ? "设备连接" : "账户")}>${device ? "DEVICE HANDOFF" : "ACCOUNT"}</p>
          <h1 ${copy(title, zhTitle)}>${title}</h1>
          <p class="hero-copy" ${copy(description, zhDescription)}>${description}</p>
        </section>
        <div class="content-grid">
          ${device ? devicePanel() : authPanel(options)}
          ${device ? authPanel(options) : `<aside class="info-panel" aria-label="Ziki notes">
            <div class="info-block">
              <p class="section-kicker" ${copy("WHAT TO EXPECT", "使用说明")}>WHAT TO EXPECT</p>
              <h2 class="info-title" ${copy("Quiet by design.", "保持安静。")}>Quiet by design.</h2>
              <p class="muted" ${copy("Your browser only receives the small amount of account information it needs. Sessions stay in secure cookies; this page does not put tokens in local storage or URLs.", "浏览器只会收到必要的少量账户信息。会话保存在安全 Cookie 中；本页面不会把令牌放进本地存储或 URL。")}>Your browser only receives the small amount of account information it needs. Sessions stay in secure cookies; this page does not put tokens in local storage or URLs.</p>
            </div>
            <div class="info-block">
              <p class="section-kicker" ${copy("CURRENTLY", "当前状态")}>CURRENTLY</p>
              <h2 class="info-title" ${copy("Hosted dictation is not available yet.", "托管听写尚不可用。")}>Hosted dictation is not available yet.</h2>
              <p class="muted" ${copy("BYOK works without a Ziki login. Sign in here only when you need an account or a Mac approval.", "BYOK 无需 Ziki 登录即可使用。只有需要账户或批准 Mac 时才在这里登录。")}>BYOK works without a Ziki login. Sign in here only when you need an account or a Mac approval.</p>
            </div>
          </aside>`}
        </div>
      </main>
      <footer><span ${copy("Ziki · account access", "Ziki · 账户访问")}>Ziki · account access</span></footer>
    </div>
    <script nonce="${pageNonce}">
      (() => {
        const isDevicePage = ${device ? "true" : "false"};
        const cloudEnabled = ${options.enabled ? "true" : "false"};
        const callbackURL = isDevicePage ? "/device" : "/account";
        const signedOut = document.querySelector("[data-auth-signed-out]");
        const signedIn = document.querySelector("[data-auth-signed-in]");
        let signedInSession = false;
        let language = "en";
        const text = (en, zh) => language === "zh" ? zh : en;
        const authStatuses = document.querySelectorAll("[data-auth-status]");
        const setAuthStatus = (message) => authStatuses.forEach((node) => { node.textContent = message; });
        const hasOAuthError = (() => {
          try { return new URL(window.location.href).searchParams.has("error"); }
          catch { return false; }
        })();
        const setDeviceStatus = (message) => {
          const node = document.querySelector("[data-device-status]");
          if (node) node.textContent = message;
        };
        const errorCopy = (code) => {
          const messages = {
            unauthorized: ["Please sign in first, then try again.", "请先登录，然后重试。"],
            invalid_code: ["That code is not valid. Check the code on your Mac and try again.", "代码无效。请检查 Mac 上的代码，然后重试。"],
            authorization_pending: ["Your Mac is still waiting for approval. Keep Ziki open and try again.", "你的 Mac 仍在等待批准。请保持 Ziki 打开，然后重试。"],
            expired_token: ["This code expired. Start a new sign-in from Ziki on your Mac.", "代码已过期。请在 Mac 上从 Ziki 发起新的登录。"],
            invalid_grant: ["This code is no longer valid. Start a new sign-in from Ziki on your Mac.", "代码已失效。请在 Mac 上从 Ziki 发起新的登录。"],
            rate_limit_exceeded: ["Too many attempts. Wait a moment and try again.", "尝试次数过多。请稍等片刻再重试。"],
            service_unavailable: ["Sign-in is temporarily unavailable. Please try again later.", "登录服务暂不可用，请稍后重试。"],
            origin_not_allowed: ["This request came from an untrusted origin. Reopen Ziki and try again.", "请求来自不受信任的来源。请重新打开 Ziki，然后重试。"]
          };
          const message = messages[code] || ["That request could not be completed. Check the details and try again.", "请求未完成。请检查详情，然后重试。"];
          return text(message[0], message[1]);
        };
        const readJson = async (response) => {
          const type = response.headers.get("content-type") || "";
          if (!type.includes("application/json")) return null;
          try { return await response.json(); } catch { return null; }
        };
        const api = async (path, init = {}) => {
          const headers = new Headers(init.headers || {});
          if (init.body !== undefined) headers.set("Content-Type", "application/json");
          try {
            const response = await fetch(path, { ...init, headers, credentials: "same-origin", signal: AbortSignal.timeout(15000) });
            let data = await readJson(response);
            if (!response.ok) data = { error: response.status === 429 ? "rate_limit_exceeded" : response.status === 503 ? "service_unavailable" : response.status === 401 ? "unauthorized" : (data?.error || data?.code) };
            return { response, data };
          } catch {
            return { response: null, data: null };
          }
        };
        const safeRedirect = (value) => {
          if (typeof value !== "string" || value.length > 2048) return null;
          try {
            const target = new URL(value, window.location.origin);
            if (target.origin === window.location.origin || target.protocol === "https:") return target.href;
          } catch { /* An invalid provider URL is never navigated to. */ }
          return null;
        };
        const setSignedIn = (data) => {
          const user = data && data.user;
          if (!user || typeof user.email !== "string" || typeof user.id !== "string") return false;
          const emailNode = document.querySelector("[data-user-email]");
          const idNode = document.querySelector("[data-user-id]");
          const secondsNode = document.querySelector("[data-available-seconds]");
          if (emailNode) emailNode.textContent = user.email;
          if (idNode) idNode.textContent = user.id;
          if (secondsNode) {
            const seconds = Number(data.availableSeconds);
            secondsNode.textContent = Number.isFinite(seconds) && seconds >= 0 ? String(Math.floor(seconds)) : "—";
          }
          if (signedOut) signedOut.hidden = true;
          if (signedIn) signedIn.hidden = false;
          signedInSession = true;
          document.documentElement.setAttribute("data-signed-in", "true");
          return true;
        };
        const loadSession = async () => {
          if (!cloudEnabled || !signedOut) return;
          if (hasOAuthError) setAuthStatus(text("Sign-in failed. Check the provider and try again.", "登录失败。请检查服务商，然后重试。"));
          const result = await api("/v1/me", { method: "GET" });
          if (result.response && result.response.ok && setSignedIn(result.data)) return;
          if (result.response && result.response.status !== 401) setAuthStatus(errorCopy(result.data && result.data.error));
        };
        document.querySelectorAll("[data-provider]").forEach((button) => {
          button.addEventListener("click", async () => {
            const provider = button.getAttribute("data-provider");
            if (provider !== "google") return;
            button.disabled = true;
            setAuthStatus(text("Opening secure sign-in…", "正在打开安全登录…"));
            const result = await api("/api/auth/sign-in/social", {
              method: "POST",
              body: JSON.stringify({ provider, callbackURL })
            });
            const target = result.response && result.response.ok && result.data ? safeRedirect(result.data.url) : null;
            if (target) window.location.assign(target);
            else {
              button.disabled = false;
              setAuthStatus(result.response ? errorCopy(result.data && result.data.error) : text("Network error. Check your connection and try again.", "网络错误。请检查连接，然后重试。"));
            }
          });
        });
        const emailForm = document.querySelector("[data-email-form]");
        const otpForm = document.querySelector("[data-otp-form]");
        const emailInput = document.querySelector("#account-email");
        const otpInput = document.querySelector("#account-otp");
        const changeEmail = document.querySelector("[data-change-email]");
        const resendOtp = document.querySelector("[data-resend-otp]");
        const resendCountdown = document.querySelector("[data-resend-countdown]");
        let pendingEmail = "";
        let resendTimer = 0;
        let resendRemaining = 0;
        const updateResendState = () => {
          if (!resendOtp) return;
          resendOtp.disabled = resendRemaining > 0;
          if (resendCountdown) resendCountdown.textContent = resendRemaining > 0 ? text(" in " + resendRemaining + "s", "（" + resendRemaining + " 秒后）") : "";
        };
        const stopResendCooldown = () => {
          if (resendTimer) window.clearTimeout(resendTimer);
          resendTimer = 0;
          resendRemaining = 0;
          updateResendState();
        };
        const startResendCooldown = () => {
          if (resendTimer) window.clearTimeout(resendTimer);
          resendRemaining = 60;
          const tick = () => {
            updateResendState();
            if (resendRemaining === 0) { resendTimer = 0; return; }
            resendRemaining -= 1;
            resendTimer = window.setTimeout(tick, 1000);
          };
          tick();
        };
        if (emailForm && otpForm && emailInput && otpInput) {
          const sendOtp = async (email, submit) => {
            if (submit) submit.disabled = true;
            if (changeEmail) changeEmail.disabled = true;
            const result = await api("/api/auth/email-otp/send-verification-otp", {
              method: "POST",
              body: JSON.stringify({ email, type: "sign-in" })
            });
            if (changeEmail) changeEmail.disabled = false;
            if (result.response && result.response.ok) {
              pendingEmail = email;
              emailForm.hidden = true;
              otpForm.hidden = false;
              otpInput.value = "";
              startResendCooldown();
              otpInput.focus();
              setAuthStatus(text("Code sent. Check your inbox.", "验证码已发送，请查看收件箱。"));
              return true;
            }
            if (submit) submit.disabled = false;
            setAuthStatus(result.response ? errorCopy(result.data && result.data.error) : text("Network error. Check your connection and try again.", "网络错误。请检查连接，然后重试。"));
            return false;
          };
          emailForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const email = emailInput.value.trim();
            if (!email || !email.includes("@")) { setAuthStatus(text("Enter a valid email address first.", "请先输入有效的邮箱地址。")); return; }
            await sendOtp(email, emailForm.querySelector("button"));
          });
          otpForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const otp = otpInput.value.trim();
            if (!pendingEmail || !/^\\d{8}$/.test(otp)) { setAuthStatus(text("Enter the 8-digit verification code from your inbox.", "请输入收件箱中的 8 位验证码。")); return; }
            const submit = otpForm.querySelector("button");
            if (submit) submit.disabled = true;
            const result = await api("/api/auth/sign-in/email-otp", {
              method: "POST",
              body: JSON.stringify({ email: pendingEmail, otp })
            });
            if (result.response && result.response.ok && setSignedIn(result.data)) {
              setAuthStatus("");
              await loadSession();
            }
            else {
              if (submit) submit.disabled = false;
              setAuthStatus(result.response ? errorCopy(result.data && result.data.error) : text("Network error. Check your connection and try again.", "网络错误。请检查连接，然后重试。"));
            }
          });
          if (changeEmail) changeEmail.addEventListener("click", () => {
            pendingEmail = "";
            stopResendCooldown();
            emailForm.reset();
            otpForm.reset();
            emailForm.hidden = false;
            otpForm.hidden = true;
            const submit = emailForm.querySelector("button");
            if (submit) submit.disabled = false;
            emailInput.focus();
            setAuthStatus(text("Enter the email you want to use.", "请输入要使用的邮箱。"));
          });
          if (resendOtp) resendOtp.addEventListener("click", async () => {
            if (!pendingEmail || resendOtp.disabled) return;
            resendOtp.disabled = true;
            await sendOtp(pendingEmail, resendOtp);
            updateResendState();
          });
        }
        const signOut = document.querySelector("[data-sign-out]");
        if (signOut) signOut.addEventListener("click", async () => {
          signOut.disabled = true;
          const result = await api("/api/auth/sign-out", { method: "POST", body: "{}" });
          if (result.response && result.response.ok) {
            if (signedIn) signedIn.hidden = true;
            if (signedOut) signedOut.hidden = false;
            signedInSession = false;
            document.documentElement.removeAttribute("data-signed-in");
            pendingEmail = "";
            stopResendCooldown();
            if (emailForm && otpForm && emailInput && otpInput) {
              emailForm.reset();
              otpForm.reset();
              emailForm.hidden = false;
              otpForm.hidden = true;
              const emailSubmit = emailForm.querySelector("button");
              const otpSubmit = otpForm.querySelector("button");
              if (emailSubmit) emailSubmit.disabled = false;
              if (otpSubmit) otpSubmit.disabled = false;
            }
            if (reviewForm) reviewForm.reset();
            resetReview(true);
            setDeviceStatus("");
            signOut.disabled = false;
            setAuthStatus(text("You are signed out.", "你已退出登录。"));
          } else {
            signOut.disabled = false;
            setAuthStatus(result.response ? errorCopy(result.data && result.data.error) : text("Network error. Check your connection and try again.", "网络错误。请检查连接，然后重试。"));
          }
        });
        const reviewForm = document.querySelector("[data-device-review-form]");
        const codeInput = document.querySelector("#device-user-code");
        const reviewCard = document.querySelector("[data-device-review]");
        const reviewedCodeNode = document.querySelector("[data-device-code]");
        const approve = document.querySelector("[data-device-approve]");
        const deny = document.querySelector("[data-device-deny]");
        let reviewedCode = "";
        let reviewRequestId = 0;
        const resetReview = (clearInput = false) => {
          reviewRequestId += 1;
          reviewedCode = "";
          if (reviewCard) reviewCard.hidden = true;
          if (approve) approve.disabled = true;
          if (deny) deny.disabled = true;
          if (reviewedCodeNode) reviewedCodeNode.textContent = "—";
          if (clearInput && codeInput) codeInput.value = "";
        };
        if (reviewForm && codeInput) {
          codeInput.addEventListener("input", () => resetReview());
          reviewForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const userCode = codeInput.value.trim();
            resetReview();
            const requestId = reviewRequestId;
            if (!userCode) { setDeviceStatus(text("Enter the code shown in Ziki on your Mac.", "请输入 Mac 上 Ziki 显示的代码。")); return; }
            if (!signedInSession) { setDeviceStatus(text("Please sign in first, then review this Mac code.", "请先登录，然后查看这个 Mac 代码。")); return; }
            const result = await api("/api/auth/device?user_code=" + encodeURIComponent(userCode), { method: "GET" });
            if (requestId !== reviewRequestId) return;
            if (!(result.response && result.response.ok)) {
              setDeviceStatus(result.response ? errorCopy(result.data && result.data.error) : text("Network error. Check your connection and try again.", "网络错误。请检查连接，然后重试。"));
              return;
            }
            const review = result.data;
            if (!review || review.user_code !== userCode || review.client_id !== "ziki-macos" || review.status !== "pending") {
              const stateMessage = review && review.status === "approved"
                ? text("This code is already approved. Return to Ziki on your Mac.", "此代码已批准。请回到 Mac 上的 Ziki。")
                : review && review.status === "denied"
                  ? text("This code was denied. Start a new request from Ziki on your Mac.", "此代码已被拒绝。请在 Mac 上的 Ziki 发起新请求。")
                  : text("This code is not available for approval. Check the code and try again.", "此代码无法批准。请检查代码，然后重试。");
              setDeviceStatus(stateMessage);
              return;
            }
            reviewedCode = review.user_code;
            const clientNode = document.querySelector("[data-device-client]");
            const scopeNode = document.querySelector("[data-device-scope]");
            if (reviewedCodeNode) reviewedCodeNode.textContent = review.user_code;
            if (clientNode) clientNode.textContent = review.client_id;
            if (scopeNode) scopeNode.textContent = typeof review.scope === "string" ? review.scope : text("Account access", "账户访问");
            if (reviewCard) reviewCard.hidden = false;
            if (approve) approve.disabled = false;
            if (deny) deny.disabled = false;
            setDeviceStatus("");
          });
        }
        const decideDevice = async (path, button, successMessage) => {
          if (!reviewedCode || !button || button.disabled) return;
          const requestId = reviewRequestId;
          approve.disabled = true;
          deny.disabled = true;
          const result = await api(path, { method: "POST", body: JSON.stringify({ userCode: reviewedCode }) });
          if (requestId !== reviewRequestId) return;
          if (result.response && result.response.ok) {
            if (reviewCard) reviewCard.hidden = true;
            setDeviceStatus(text(successMessage[0], successMessage[1]));
            reviewedCode = "";
          } else {
            resetReview();
            setDeviceStatus(result.response ? errorCopy(result.data && result.data.error) : text("Network error. Check your connection and try again.", "网络错误。请检查连接，然后重试。"));
          }
        };
        if (approve) approve.addEventListener("click", () => decideDevice("/api/auth/device/approve", approve, ["Approved. You can return to Ziki on your Mac.", "已批准。你可以回到 Mac 上的 Ziki。"]));
        if (deny) deny.addEventListener("click", () => decideDevice("/api/auth/device/deny", deny, ["Denied. The code can no longer connect this Mac.", "已拒绝。此代码无法再连接这台 Mac。"]));
        const languageToggle = document.querySelector("[data-language-toggle]");
        if (languageToggle) languageToggle.addEventListener("click", () => {
          language = language === "en" ? "zh" : "en";
          document.documentElement.lang = language;
          document.querySelectorAll("[data-en][data-zh]").forEach((node) => {
            const value = node.getAttribute(language === "zh" ? "data-zh" : "data-en");
            if (value) node.textContent = value;
          });
          updateResendState();
          languageToggle.textContent = language === "zh" ? "EN" : "中文";
          languageToggle.setAttribute("aria-label", language === "zh" ? "Switch to English" : "切换到中文");
        });
        loadSession();
      })();
    </script>
  </body>
</html>`;
}

export function accountPage(options: AccountPageOptions): Response {
  const pageNonce = nonce();
  const policy = [
    "default-src 'none'",
    `script-src 'nonce-${pageNonce}'`,
    `style-src 'nonce-${pageNonce}'`,
    "connect-src 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "base-uri 'none'",
    "object-src 'none'"
  ].join("; ");
  return new Response(pageMarkup(options, pageNonce), {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=UTF-8",
      "Content-Security-Policy": policy,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer"
    }
  });
}
