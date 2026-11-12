import { env } from "cloudflare:workers";
import { describe, it, expect } from "vitest";
import worker from "../src/index";
import { dictations, cloudEnabled, type SpeechRuntime } from "../src/dictations";
import { Ledger } from "../src/ledger";

const origin = "http://127.0.0.1:8787";
const settings = () => ({ ...env, ENVIRONMENT: "local", AUTH_ENABLED: "true", CLOUD_ENABLED: "true",
  BETTER_AUTH_SECRET: "local-fixture-secret-longer-than-32-characters", BAILIAN_API_KEY: "fixture-key-never-real", BAILIAN_WORKSPACE_ID: "fixture" } as unknown as Env);
const pause = (ms = 20) => new Promise(resolve => setTimeout(resolve,ms));
async function fixture(verified = true, seconds = 5) {
  const user = crypto.randomUUID(); const token = crypto.randomUUID(); const timestamp = Date.now();
  await env.DB.batch([
    env.DB.prepare('INSERT INTO "user" (id,name,email,emailVerified,createdAt,updatedAt) VALUES (?,?,?,?,?,?)')
      .bind(user,"Fixture",`${user}@example.invalid`,verified ? 1 : 0,timestamp,timestamp),
    env.DB.prepare('INSERT INTO "session" (id,token,userId,expiresAt,createdAt,updatedAt) VALUES (?,?,?,?,?,?)')
      .bind(crypto.randomUUID(),token,user,timestamp+600000,timestamp,timestamp),
  ]);
  const ledger = new Ledger(env.DB); const now = Math.floor(timestamp/1000);
  await ledger.grant({ userId: user, source: crypto.randomUUID(),kind: "trial",seconds,startsAt: now,expiresAt: now+3600 });
  const request = (path = "", method = "GET", body?: unknown, extra: HeadersInit = {}) => new Request(`${origin}/v1/dictations${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, ...(body ? { "Content-Type": "application/json" } : {}), ...extra },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const reserve = async () => {
    const response = await dictations(request("","POST",{ idempotencyKey: crypto.randomUUID(), maxSeconds: 300 }),settings());
    return response.json<{ id: string; maxSeconds: number; status: string }>();
  };
  return { user, token, ledger, request, reserve, now };
}
function transport(options: { text?: string; cleanup?: string; finishReason?: string; status?: number; noStart?: boolean; noFinish?: boolean; hangCleanup?: boolean; failConnect?: boolean } = {}) {
  let upstream: WebSocket | undefined; let task = ""; let calls = 0; let cleaned = 0; let closed = false; let received = 0;
  let cleanupBody: Record<string, unknown> | undefined;
  let providerSocket: WebSocket | undefined;
  const urls: string[] = [];
  const emit = (event: string, payload?: object) => upstream!.send(JSON.stringify({ header: { task_id: task, event },payload }));
  const io: SpeechRuntime = { setTimeout,clearTimeout, fetch: (async (_url: string | URL | Request, init?: RequestInit) => {
    urls.push(String(_url));
    expect(init?.redirect).toBe("manual");
    if (init?.method === "POST") {
      cleaned++; cleanupBody = JSON.parse(String(init.body));
      if (options.hangCleanup) return new Promise((_resolve,reject) => init.signal?.addEventListener("abort", () => reject(new Error("fixture abort"))));
      return Response.json({ choices: [{ finish_reason: options.finishReason ?? "stop", message: { content: options.cleanup ?? "Cleaned." } }] },{ status: options.status ?? 200 });
    }
    calls++;
    if (options.failConnect) throw new Error("sensitive provider detail");
    const pair = new WebSocketPair(); providerSocket = pair[0]; upstream = pair[1]; upstream.binaryType = "arraybuffer"; upstream.accept();
    upstream.addEventListener("close", () => { closed = true; });
    upstream.addEventListener("message", e => {
      if (typeof e.data !== "string") { received += e.data.byteLength; return; }
      const command = JSON.parse(e.data); task = command.header.task_id;
      if (command.header.action === "run-task" && !options.noStart) emit("task-started");
      if (command.header.action === "finish-task" && !options.noFinish) {
        if (options.text !== "") emit("result-generated",{ output: { sentence: { sentence_id: 0,text: options.text ?? "Raw.",sentence_end: true } } });
        emit("task-finished");
      }
    });
    return new Response(null,{ status: 101,webSocket: pair[0] });
  }) as typeof fetch };
  return { io, emit, urls, failSocket: () => providerSocket!.dispatchEvent(new Event("error")), get calls() { return calls; },get cleaned() { return cleaned; },get closed() { return closed; },get received() { return received; },get cleanupBody() { return cleanupBody; } };
}
function clock(io: SpeechRuntime) {
  const callbacks = new Map<number, Set<() => void>>();
  return { io: { ...io, setTimeout: (fn: () => void, ms: number) => {
    const wrapped = () => { callbacks.get(ms)?.delete(wrapped); fn(); };
    if (!callbacks.has(ms)) callbacks.set(ms,new Set()); callbacks.get(ms)!.add(wrapped);
    return wrapped as unknown as ReturnType<typeof setTimeout>;
  }, clearTimeout: (id: ReturnType<typeof setTimeout>) => { for (const set of callbacks.values()) set.delete(id as unknown as () => void); } },
  fire: (ms: number) => { for (const fn of [...callbacks.get(ms) ?? []]) fn(); } };
}
async function socket(f: Awaited<ReturnType<typeof fixture>>, id: string, io: SpeechRuntime) {
  const response = await dictations(f.request(`/${id}/stream`,"GET",undefined,{ Upgrade: "websocket" }),settings(),io);
  const ws = response.webSocket!; ws.binaryType = "arraybuffer"; ws.accept();
  const events: Record<string, unknown>[] = [];
  ws.addEventListener("message", event => { events.push(JSON.parse(String(event.data))); });
  const until = async (type: string) => {
    for (let i=0;i<150;i++) { const event = events.find(e => e.type === type); if (event) return event; await pause(10); }
    throw new Error(`missing ${type}: ${JSON.stringify(events)}`);
  };
  return { ws,events,until, start: (enabled = false, context: unknown[] = []) => ws.send(JSON.stringify({ type: "start",language: "en",cleanupEnabled: enabled,context })) };
}

describe("P2 REST bearer authorization and D1 reservations", () => {
  it("fails closed on production, missing independent flags/config, cookie-only, foreign origins, query tokens and unverified sessions", async () => {
    const f = await fixture();
    for (const override of [{ ENVIRONMENT: "production" }, { AUTH_ENABLED: "false" }, { CLOUD_ENABLED: "false" }, { BAILIAN_API_KEY: "" },{ BAILIAN_WORKSPACE_ID: "evil/path" }]) {
      expect(cloudEnabled({ ...settings(),...override } as Env)).toBe(false);
      await expect(dictations(f.request(),{ ...settings(),...override } as Env)).rejects.toMatchObject({ status: 503 });
    }
    await expect(dictations(new Request(`${origin}/v1/dictations`,{ headers: { Cookie: `better-auth.session_token=${f.token}` } }),settings())).rejects.toMatchObject({ status: 401 });
    await expect(dictations(f.request("?token=bad"),settings())).rejects.toMatchObject({ status: 401 });
    await expect(dictations(f.request("","GET",undefined,{ Origin: "https://evil.example" }),settings())).rejects.toMatchObject({ status: 403 });
    const other = await fixture(false);
    await expect(dictations(other.request(),settings())).rejects.toMatchObject({ status: 401 });
    await env.DB.prepare('DELETE FROM "session" WHERE token=?').bind(f.token).run();
    await expect(dictations(f.request(),settings())).rejects.toMatchObject({ status: 401 });
  });
  it("reserves up to balance, replays once concurrently, rejects cross-user query/cancel/claim and exposes no grant", async () => {
    const f = await fixture(); const key = crypto.randomUUID();
    const responses = await Promise.all([1,2].map(() => dictations(f.request("","POST",{ idempotencyKey: key,maxSeconds: 300 }),settings())));
    const rows = await Promise.all(responses.map(r => r.json<{ id: string; maxSeconds: number }>()));
    expect(rows[0]).toEqual(rows[1]); expect(rows[0]!.maxSeconds).toBe(5);
    const stranger = await fixture();
    for (const [path, method] of [[`/${rows[0]!.id}`,"GET"],[`/${rows[0]!.id}/cancel`,"POST"],[`/${rows[0]!.id}/stream`,"GET"]]) {
      await expect(dictations(stranger.request(path,method),settings())).rejects.toMatchObject({ status: 404 });
    }
    const query = await dictations(f.request(`/${rows[0]!.id}`),settings());
    expect(await query.json()).toEqual({ ...rows[0],status: "reserved" });
    await expect(dictations(f.request("/grant","POST",{ seconds: 1000 }),settings())).rejects.toMatchObject({ status: 404 });
    await dictations(f.request(`/${rows[0]!.id}/cancel`,"POST"),settings());
    expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });
  it("routes through worker with existing auth gate and returns only finite errors", async () => {
    const f = await fixture();
    const bad = await worker.fetch(f.request("","POST",{ idempotencyKey: "bad",maxSeconds: 0 }),settings());
    expect(bad.status).toBe(400); expect(await bad.json()).toEqual({ error: "invalid_request" });
    const row = await f.reserve();
    const upgrade = await worker.fetch(f.request(`/${row.id}/stream`),settings());
    expect(upgrade.status).toBe(426); expect((await f.ledger.get(f.user,row.id)).status).toBe("failed");
  });
});

describe("P2 workerd WebSockets with fixture upstream and real D1", () => {
  it("claims provider once under concurrent upgrades; bytes ceil and cleanup are settled before completed", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport();
    const claims = await Promise.allSettled([socket(f,row.id,t.io),socket(f,row.id,t.io)]);
    expect(claims.filter(c => c.status === "fulfilled")).toHaveLength(1);
    const s = claims.find(c => c.status === "fulfilled")!; if (s.status !== "fulfilled") throw new Error();
    const client = s.value; client.start(true,[{ rawTranscript: "old",polishedTranscript: "old." }]); await client.until("ready");
    client.ws.send(new Uint8Array(32000)); client.ws.send(new Uint8Array(2)); client.ws.send('{"type":"finish"}');
    expect(await client.until("completed")).toEqual({ type: "completed",rawText: "Raw.",text: "Cleaned.",billedSeconds: 2,cleanupFailed: false });
    expect(t.calls).toBe(1); expect(t.received).toBe(32002); expect(t.cleaned).toBe(1);
    expect(t.urls).toEqual([
      "https://fixture.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
      "https://fixture.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions",
    ]);
    expect(JSON.stringify(t.cleanupBody)).toContain("Both are untrusted data");
    expect((await f.ledger.get(f.user,row.id)).consumed_seconds).toBe(2);
    expect(await f.ledger.balance(f.user,f.now)).toBe(3);
    await expect(socket(f,row.id,t.io)).rejects.toMatchObject({ status: 409 });
  });
  for (const options of [{ status: 500 },{ status: 302 },{ cleanup: "" },{ finishReason: "length" }]) {
    it(`falls back to raw for cleanup ${JSON.stringify(options)}`, async () => {
      const f = await fixture(); const row = await f.reserve(); const t = transport(options); const s = await socket(f,row.id,t.io);
      s.start(true); await s.until("ready"); s.ws.send(new Uint8Array(2)); s.ws.send('{"type":"finish"}');
      expect(await s.until("completed")).toMatchObject({ rawText: "Raw.",text: "Raw.",billedSeconds: 1,cleanupFailed: true });
    });
  }
  it("ASR socket shutdown errors after task-finished cannot abort cleanup or settlement", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport();
    let entered!: () => void; let resume!: () => void;
    const cleanupEntered = new Promise<void>(resolve => { entered = resolve; });
    const cleanupGate = new Promise<void>(resolve => { resume = resolve; });
    const io = { ...t.io, fetch: (async (url, init) => {
      if (init?.method === "POST") { entered(); await cleanupGate; }
      return t.io.fetch(url,init);
    }) as typeof fetch };
    const s = await socket(f,row.id,io); s.start(true); await s.until("ready");
    s.ws.send(new Uint8Array(32000)); s.ws.send('{"type":"finish"}'); await cleanupEntered;
    t.failSocket(); resume();
    expect(await s.until("completed")).toMatchObject({ text: "Cleaned.",billedSeconds: 1,cleanupFailed: false });
    expect(s.events.some(e => e.type === "error")).toBe(false);
    expect((await f.ledger.get(f.user,row.id)).status).toBe("completed");
  });
  it("ASR socket errors before task-finished still fail and release the reservation", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport();
    const s = await socket(f,row.id,t.io); s.start(true); await s.until("ready");
    t.failSocket(); expect(await s.until("error")).toMatchObject({ code: "provider_failed" }); await pause();
    expect((await f.ledger.get(f.user,row.id)).status).toBe("failed");
    expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });
  it("empty recognition charges zero and skips cleanup", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport({ text: "" }); const s = await socket(f,row.id,t.io);
    s.start(true); await s.until("ready"); s.ws.send(new Uint8Array(32000)); s.ws.send('{"type":"finish"}');
    expect(await s.until("completed")).toMatchObject({ text: "",rawText: "",billedSeconds: 0 }); expect(t.cleaned).toBe(0);
    expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });
  for (const frame of [new Uint8Array(3),new Uint8Array(32002),'{"type":"finish","seconds":1}',JSON.stringify({ type: "start" })]) {
    it(`rejects malformed/oversized frame ${typeof frame === "string" ? frame : frame.length}`, async () => {
      const f = await fixture(); const row = await f.reserve(); const t = transport(); const s = await socket(f,row.id,t.io);
      s.start(); await s.until("ready"); s.ws.send(frame); await s.until("error"); await pause();
      expect((await f.ledger.get(f.user,row.id)).status).toBe("failed"); expect(t.closed).toBe(true); expect(await f.ledger.balance(f.user,f.now)).toBe(5);
    });
  }
  it("allows exactly the reserved byte limit; rejects overflow without charging", async () => {
    const f = await fixture(true,1); const row = await f.reserve(); const t = transport(); const s = await socket(f,row.id,t.io);
    s.start(); await s.until("ready"); s.ws.send(new Uint8Array(32000)); s.ws.send(new Uint8Array(2));
    expect(await s.until("error")).toMatchObject({ code: "invalid_audio" }); await pause();
    expect(t.received).toBe(32000); expect(await f.ledger.balance(f.user,f.now)).toBe(1);
  });
  it("same socket cancel/close immediately stops upstream and releases", async () => {
    for (const close of [false,true]) {
      const f = await fixture(); const row = await f.reserve(); const t = transport(); const s = await socket(f,row.id,t.io);
      s.start(); await s.until("ready"); if (close) s.ws.close(); else s.ws.send('{"type":"cancel"}'); await pause(40);
      expect(t.closed).toBe(true); expect((await f.ledger.get(f.user,row.id)).status).toBe("cancelled");
    }
  });
  it("remote REST cancel stops active upstream at next D1 poll, with no settlement", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport(); const c = clock(t.io); const s = await socket(f,row.id,c.io);
    s.start(); await s.until("ready"); await dictations(f.request(`/${row.id}/cancel`,"POST"),settings()); c.fire(1000);
    expect(await s.until("error")).toMatchObject({ code: "cancelled" }); await pause(); expect(t.closed).toBe(true);
    expect((await f.ledger.get(f.user,row.id)).status).toBe("cancelled"); expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });
  it("remote cancel during cleanup cannot charge or return completed", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport({ hangCleanup: true }); const c = clock(t.io); const s = await socket(f,row.id,c.io);
    s.start(true); await s.until("ready"); s.ws.send(new Uint8Array(2)); s.ws.send('{"type":"finish"}'); await pause(40);
    expect(t.cleaned).toBe(1); await dictations(f.request(`/${row.id}/cancel`,"POST"),settings()); c.fire(1000); await s.until("error"); await pause();
    expect(s.events.some(e => e.type === "completed")).toBe(false); expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });
  for (const stage of ["start","connect","finish","total","cleanup"] as const) {
    it(`bounds ${stage} timeout and releases or falls back`, async () => {
      const f = await fixture(); const row = await f.reserve(); const t = transport({ noStart: stage === "connect", noFinish: stage === "finish",hangCleanup: stage === "cleanup" }); const c = clock(t.io); const s = await socket(f,row.id,c.io);
      if (stage !== "start") { s.start(stage === "cleanup"); if (stage !== "connect") await s.until("ready"); else await pause(); }
      if (stage === "finish" || stage === "cleanup") { s.ws.send(new Uint8Array(2)); s.ws.send('{"type":"finish"}'); await pause(40); }
      c.fire(stage === "start" ? 10000 : stage === "cleanup" ? 15000 : stage === "total" ? (row.maxSeconds*1000+10000) : 30000);
      if (stage === "cleanup") expect(await s.until("completed")).toMatchObject({ text: "Raw.",cleanupFailed: true,billedSeconds: 1 });
      else { expect(await s.until("error")).toMatchObject({ code: "timeout" }); await pause(); expect(await f.ledger.balance(f.user,f.now)).toBe(5); }
    });
  }
  it("provider errors are sanitized and reservation is released", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport({ failConnect: true }); const s = await socket(f,row.id,t.io);
    s.start(); expect(await s.until("error")).toEqual({ type: "error",code: "provider_failed" }); await pause();
    expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });
  for (const fault of ["failure","timeout"] as const) {
    it(`fails closed on D1 poll ${fault} and closes upstream`, async () => {
      const f = await fixture(); const row = await f.reserve(); const t = transport(); const c = clock(t.io);
      let failing = false;
      const db = new Proxy(env.DB, { get(target,prop) {
        if (prop === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (!failing || !sql.startsWith("SELECT * FROM dictations WHERE id=")) return statement;
          return new Proxy(statement, { get(st,key) {
            if (key === "bind") return () => ({ first: () => fault === "failure" ? Promise.reject(new Error("fixture failure")) : new Promise(() => {}) });
            const value = Reflect.get(st,key); return typeof value === "function" ? value.bind(st) : value;
          } });
        };
        const value = Reflect.get(target,prop); return typeof value === "function" ? value.bind(target) : value;
      } });
      const response = await dictations(f.request(`/${row.id}/stream`,"GET",undefined,{ Upgrade: "websocket" }),{ ...settings(),DB: db },c.io);
      const ws = response.webSocket!; ws.accept(); const events: Record<string,unknown>[] = [];
      ws.addEventListener("message",e => { events.push(JSON.parse(String(e.data))); });
      ws.send(JSON.stringify({ type: "start",language: "auto",cleanupEnabled: false,context: [] })); await pause(40);
      expect(events.some(e => e.type === "ready")).toBe(true);
      failing = true; c.fire(1000); await pause(); if (fault === "timeout") c.fire(2000); await pause(40);
      expect(events).toContainEqual({ type: "error",code: "state_unavailable" }); expect(t.closed).toBe(true);
      // Restore reads; fail-closed release still uses the real D1 update.
      failing = false; expect((await f.ledger.get(f.user,row.id)).status).toBe("failed"); expect(await f.ledger.balance(f.user,f.now)).toBe(5);
    });
  }
  it("bounds pending messages while provider handshake is stalled", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport();
    let resolve!: (response: Response) => void;
    const io = { ...t.io,fetch: (() => new Promise<Response>(done => { resolve = done; })) as typeof fetch };
    const s = await socket(f,row.id,io); s.start(); await pause();
    for (let i=0;i<12;i++) s.ws.send(new Uint8Array(32000));
    expect(await s.until("error")).toMatchObject({ code: "message_too_large" });
    const late = new WebSocketPair(); late[1].accept(); let closed = false; late[1].addEventListener("close",() => { closed = true; });
    resolve(new Response(null,{ status: 101,webSocket: late[0] })); await pause(40);
    expect(closed).toBe(true); expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });
  for (const message of [JSON.stringify({ type: "start",language: ["en"],cleanupEnabled: false,context: [] }),'{"type":"start","language":"fr","cleanupEnabled":false,"context":[]}',
    JSON.stringify({ type: "start",language: "en",cleanupEnabled: false,context: [{ rawTranscript: "a".repeat(8001),polishedTranscript: "" }] }),
    JSON.stringify({ type: "start",language: "en",cleanupEnabled: false,context: [{ rawTranscript: "",polishedTranscript: "",instructions: "extra" }] })]) {
    it("rejects invalid start options without contacting provider", async () => {
      const f = await fixture(); const row = await f.reserve(); const t = transport(); const s = await socket(f,row.id,t.io);
      s.ws.send(message); expect(await s.until("error")).toMatchObject({ code: "invalid_message" }); expect(t.calls).toBe(0); await pause();
      expect(await f.ledger.balance(f.user,f.now)).toBe(5);
    });
  }
  for (const event of ["task-failed","task-started","unknown"]) {
    it(`rejects provider ${event} in audio phase`, async () => {
      const f = await fixture(); const row = await f.reserve(); const t = transport(); const s = await socket(f,row.id,t.io);
      s.start(); await s.until("ready"); t.emit(event); expect(await s.until("error")).toMatchObject({ code: "provider_failed" }); await pause();
      expect(await f.ledger.balance(f.user,f.now)).toBe(5);
    });
  }
  it("settlement condition blocks completion when REST cancel wins without waiting for poll", async () => {
    const f = await fixture(); const row = await f.reserve(); const t = transport(); const c = clock(t.io); const s = await socket(f,row.id,c.io);
    s.start(); await s.until("ready"); s.ws.send(new Uint8Array(2)); await pause();
    await dictations(f.request(`/${row.id}/cancel`,"POST"),settings()); s.ws.send('{"type":"finish"}');
    expect(await s.until("error")).toMatchObject({ code: "settlement_failed" });
    expect(s.events.some(e => e.type === "completed")).toBe(false); expect(await f.ledger.balance(f.user,f.now)).toBe(5);
  });

});

 it("distinguishes exhausted allowance from an active reservation", async () => {
   const f = await fixture(true,1);
   const row = await f.reserve();
   await expect(f.reserve()).rejects.toMatchObject({ status: 409, code: "active_dictation" });
   await f.ledger.start(f.user,row.id,f.now);
   await f.ledger.settle(f.user,row.id,1,f.now);
   await expect(f.reserve()).rejects.toMatchObject({ status: 402, code: "insufficient_balance" });
 });
