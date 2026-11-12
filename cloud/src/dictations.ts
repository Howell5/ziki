import { createAuth } from "./auth";
import { boundedRequest, HttpError, privateResponse } from "./http";
import { Ledger, LedgerError, type Dictation } from "./ledger";
import { cleanup, type Turn } from "./cleanup";

export function cloudEnabled(env: Env): boolean {
  return ["local", "staging"].includes(String(env.ENVIRONMENT)) && String(env.CLOUD_ENABLED) === "true" &&
    String(env.AUTH_ENABLED) === "true" && env.BETTER_AUTH_SECRET?.length >= 32 &&
    /^\S{8,512}$/.test(env.BAILIAN_API_KEY ?? "") && /^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$/.test(env.BAILIAN_WORKSPACE_ID ?? "");
}
const now = () => Math.floor(Date.now() / 1000);
const view = (row: Dictation) => ({ id: row.id, maxSeconds: row.reserved_seconds, status: row.status });
function object(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
function exact(value: Record<string, unknown>, keys: string[]) {
  return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

// Only internal imports can inject transport/timers; no request or binding selects a mock.
export interface SpeechRuntime {
  fetch: typeof fetch;
  setTimeout: (callback: () => void, ms: number) => ReturnType<typeof setTimeout>;
  clearTimeout: (timer: ReturnType<typeof setTimeout>) => void;
}
const runtime: SpeechRuntime = { fetch: (...args) => fetch(...args), setTimeout, clearTimeout };

export async function dictations(request: Request, env: Env, io = runtime, retain: (work: Promise<unknown>) => void = () => {}): Promise<Response> {
  if (!cloudEnabled(env)) throw new HttpError("cloud_not_configured", 503);
  const url = new URL(request.url);
  if (url.origin !== env.AUTH_ORIGIN || (request.headers.has("origin") && request.headers.get("origin") !== env.AUTH_ORIGIN)) {
    throw new HttpError("origin_not_allowed", 403);
  }
  if (url.search || !/^Bearer [^\s]+$/i.test(request.headers.get("authorization") ?? "")) throw new HttpError("unauthorized", 401);
  // Cookie must never rescue an invalid bearer.
  const headers = new Headers({ Authorization: request.headers.get("authorization")! });
  const session = await createAuth(env).api.getSession({ headers });
  if (!session?.user.emailVerified) throw new HttpError("unauthorized", 401);
  const ledger = new Ledger(env.DB); const user = session.user.id;
  try {
    if (url.pathname === "/v1/dictations" && request.method === "POST") {
      const body: unknown = await (await boundedRequest(request, 1024)).json().catch(() => null);
      if (!object(body) || !exact(body, ["idempotencyKey", "maxSeconds"]) || typeof body.idempotencyKey !== "string" ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.idempotencyKey) ||
          typeof body.maxSeconds !== "number" || !Number.isInteger(body.maxSeconds) || body.maxSeconds < 1 || body.maxSeconds > 300) {
        throw new HttpError("invalid_request", 400);
      }
      return privateResponse(Response.json(view(await ledger.reserveUpTo(user,body.idempotencyKey,body.maxSeconds,now()))));
    }
    const match = /^\/v1\/dictations\/([0-9a-f-]{36})(?:\/(cancel|stream))?$/.exec(url.pathname);
    if (!match) throw new HttpError("not_found", 404);
    const id = match[1]!;
    await ledger.expire(user,now());
    const row = await ledger.get(user,id);
    if (!match[2] && request.method === "GET") return privateResponse(Response.json(view(row)));
    if (match[2] === "cancel" && request.method === "POST") return privateResponse(Response.json(view(await ledger.release(user,id,"cancelled",now()))));
    if (match[2] !== "stream" || request.method !== "GET") throw new HttpError("not_found", 404);
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      if (row.status === "reserved") await ledger.release(user,id,"failed",now());
      throw new HttpError("upgrade_required", 426);
    }
    if (!await ledger.start(user,id,now())) throw new HttpError("invalid_state", 409);
    try {
      const pair = new WebSocketPair();
      new SpeechStream(pair[1],ledger,row,env,io,retain);
      return new Response(null, { status: 101, webSocket: pair[0], headers: { "Cache-Control": "no-store" } });
    } catch { await ledger.release(user,id,"failed",now()); throw new HttpError("stream_failed", 500); }
  } catch (error) {
    if (error instanceof LedgerError) {
      if (error.code === "unavailable") {
        const active = await env.DB.prepare("SELECT id FROM dictations WHERE user_id=? AND status IN ('reserved','processing') AND expires_at>?")
          .bind(user,now()).first();
        throw new HttpError(active ? "active_dictation" : "insufficient_balance", active ? 409 : 402);
      }
      throw new HttpError(error.code, error.code === "not_found" ? 404 : 409);
    }
    throw error;
  }
}

type Phase = "start" | "connecting" | "audio" | "finishing" | "cleanup" | "done";
class SpeechStream {
  private phase: Phase = "start";
  private upstream?: WebSocket;
  private abort = new AbortController();
  private timers = new Set<ReturnType<typeof setTimeout>>();
  private stageTimer?: ReturnType<typeof setTimeout>;
  private queue = Promise.resolve();
  private queuedBytes = 0;
  private queuedCount = 0;
  private bytes = 0;
  private segments = new Map<number, string>();
  private final = new Set<number>();
  private options?: { language: string; cleanupEnabled: boolean; context: Turn[] };
  private task = crypto.randomUUID();
  constructor(private client: WebSocket, private ledger: Ledger, private row: Dictation, private env: Env, private io: SpeechRuntime, private retain: (work: Promise<unknown>) => void) {
    client.binaryType = "arraybuffer"; client.accept();
    client.addEventListener("message", event => {
      // Cancellation bypasses a pending provider connection/cleanup or database read.
      if (typeof event.data === "string" && event.data.length <= 64) {
        try { const msg = JSON.parse(event.data); if (object(msg) && exact(msg,["type"]) && msg.type === "cancel") { this.stop("cancelled", "cancelled"); return; } } catch { /* normal validation below */ }
      }
      this.enqueue(event.data, false);
    });
    client.addEventListener("close", () => this.stop("cancelled","cancelled"));
    client.addEventListener("error", () => this.stop("stream_failed"));
    this.deadline(10000); this.timer(() => this.stop("timeout"), Math.max(1, row.expires_at-now())*1000);
    this.timer(() => { void this.poll(); },1000);
  }
  private timer(fn: () => void, ms: number) {
    const id = this.io.setTimeout(() => { this.timers.delete(id); fn(); },ms); this.timers.add(id); return id;
  }
  private deadline(ms: number) {
    if (this.stageTimer) { this.io.clearTimeout(this.stageTimer); this.timers.delete(this.stageTimer); }
    this.stageTimer = this.timer(() => this.stop("timeout"),ms);
  }
  private close(socket?: WebSocket) { try { socket?.close(1000); } catch { /* already closed */ } }
  private send(value: object) { this.client.send(JSON.stringify(value)); }
  private dispose() {
    this.abort.abort(); this.close(this.upstream);
    for (const id of this.timers) this.io.clearTimeout(id);
    this.timers.clear(); this.segments.clear(); this.final.clear(); this.options = undefined;
  }
  private stop(code: string, status: "failed" | "cancelled" = "failed") {
    if (this.phase === "done") return;
    this.phase = "done"; this.dispose();
    try { this.send({ type: "error", code }); } catch { /* disconnected */ }
    this.close(this.client);
    // D1 failure still fails closed; reservation expiry is the durable fallback.
    this.retain(this.ledger.release(this.row.user_id,this.row.id,status,now()).catch(() => {}));
  }
  private async poll() {
    if (this.phase === "done") return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const row = await Promise.race([this.ledger.get(this.row.user_id,this.row.id), new Promise<never>((_,reject) => {
        timer = this.timer(() => reject(new Error("state_unavailable")),2000);
      })]);
      if (this.abort.signal.aborted) return;
      if (row.status !== "processing" || row.expires_at <= now()) { this.stop("cancelled","cancelled"); return; }
      this.timer(() => { void this.poll(); },1000);
    } catch { this.stop("state_unavailable"); }
    finally { if (timer) { this.io.clearTimeout(timer); this.timers.delete(timer); } }
  }
  private enqueue(data: string | ArrayBuffer, provider: boolean) {
    if (this.phase === "done") return;
    const size = typeof data === "string" ? new TextEncoder().encode(data).length : data.byteLength;
    if (size > (provider ? 65536 : typeof data === "string" ? 32768 : 32000) || this.queuedBytes+size > 262144 || this.queuedCount >= 64) { this.stop("message_too_large"); return; }
    this.queuedBytes += size; this.queuedCount++;
    this.queue = this.queue.then(async () => {
      if (this.phase === "done") return;
      if (provider) await this.provider(data); else await this.input(data);
    }).catch(() => this.stop(provider ? "provider_failed" : "invalid_message"))
      .finally(() => { this.queuedBytes -= size; this.queuedCount--; });
  }
  private async input(data: string | ArrayBuffer) {
    if (typeof data !== "string") {
      if (this.phase !== "audio" || !data.byteLength || data.byteLength % 2 || this.bytes+data.byteLength > this.row.reserved_seconds*32000) { this.stop("invalid_audio"); return; }
      this.bytes += data.byteLength; this.upstream!.send(data); return;
    }
    const msg: unknown = JSON.parse(data);
    if (!object(msg)) throw new Error();
    if (msg.type === "finish" && exact(msg,["type"]) && this.phase === "audio") {
      this.phase = "finishing"; this.deadline(30000);
      this.upstream!.send(JSON.stringify({ header: { action: "finish-task", task_id: this.task, streaming: "duplex" }, payload: { input: {} } })); return;
    }
    if (this.phase !== "start" || msg.type !== "start" || !exact(msg,["type","language","cleanupEnabled","context"]) ||
        typeof msg.language !== "string" || !["auto","zh","en"].includes(msg.language) || typeof msg.cleanupEnabled !== "boolean" || !Array.isArray(msg.context) || msg.context.length > 3) throw new Error();
    let length = 0;
    for (const turn of msg.context) {
      if (!object(turn) || !exact(turn,["rawTranscript","polishedTranscript"]) || typeof turn.rawTranscript !== "string" || typeof turn.polishedTranscript !== "string") throw new Error();
      length += Array.from(turn.rawTranscript).length + Array.from(turn.polishedTranscript).length;
    }
    if (length > 8000) throw new Error();
    this.options = msg as typeof this.options;
    this.phase = "connecting"; this.deadline(30000);
    const host = `${this.env.BAILIAN_WORKSPACE_ID}.cn-beijing.maas.aliyuncs.com`;
    const response = await this.io.fetch(`https://${host}/api-ws/v1/inference`, { headers: {
      Upgrade: "websocket", Authorization: `Bearer ${this.env.BAILIAN_API_KEY}`, "X-DashScope-WorkSpace": this.env.BAILIAN_WORKSPACE_ID,
    }, signal: this.abort.signal, redirect: "manual" }).catch(() => { this.stop("provider_failed"); return null; });
    if (!response) return;
    const socket = response.webSocket;
    if (this.abort.signal.aborted) { if (socket) { socket.accept(); this.close(socket); } else await response.body?.cancel(); return; }
    if (response.status !== 101 || !socket) { await response.body?.cancel(); this.stop("provider_failed"); return; }
    this.upstream = socket; socket.binaryType = "arraybuffer"; socket.accept();
    socket.addEventListener("message", event => this.enqueue(event.data,true));
    socket.addEventListener("close", () => { if (this.phase !== "cleanup") this.stop("provider_failed"); });
    socket.addEventListener("error", () => { if (this.phase !== "cleanup") this.stop("provider_failed"); });
    socket.send(JSON.stringify({ header: { action: "run-task", task_id: this.task, streaming: "duplex" }, payload: {
      task_group: "audio", task: "asr", function: "recognition", model: "fun-asr-realtime", input: {},
      parameters: { format: "pcm", sample_rate: 16000, semantic_punctuation_enabled: false, max_sentence_silence: 800,
        ...(msg.language !== "auto" ? { language_hints: [msg.language] } : {}) },
    } }));
  }
  private async provider(data: string | ArrayBuffer) {
    if (typeof data !== "string") throw new Error();
    const msg = JSON.parse(data); const header = msg?.header;
    if (!object(header) || header.task_id !== this.task || typeof header.event !== "string") throw new Error();
    if (header.event === "task-started" && this.phase === "connecting") {
      this.phase = "audio"; this.deadline(this.row.reserved_seconds*1000+10000); this.send({ type: "ready" }); return;
    }
    if (header.event === "result-generated" && ["audio","finishing"].includes(this.phase)) {
      const sentence = msg?.payload?.output?.sentence;
      if (!object(sentence)) throw new Error();
      if (sentence.heartbeat === true) return;
      if (!Number.isSafeInteger(sentence.sentence_id) || Number(sentence.sentence_id) < 0 || Number(sentence.sentence_id) > 4095 ||
          typeof sentence.text !== "string" || typeof sentence.sentence_end !== "boolean") throw new Error();
      const id = Number(sentence.sentence_id);
      if (this.final.has(id)) throw new Error();
      this.segments.set(id,sentence.text); if (sentence.sentence_end) this.final.add(id);
      const text = this.raw(); if (text.length > 64000) throw new Error();
      this.send({ type: sentence.sentence_end ? "segmentFinal" : "hypothesis", text }); return;
    }
    if (header.event !== "task-finished" || this.phase !== "finishing") throw new Error();
    this.phase = "cleanup"; this.close(this.upstream);
    const rawText = this.raw().trim(); let text = rawText; let cleanupFailed = false;
    this.deadline(20000);
    if (rawText && this.options!.cleanupEnabled) {
      // Timeout must race the complete body read, not just response headers.
      let timeout: ReturnType<typeof setTimeout> | undefined;
      try {
        text = await Promise.race([cleanup(rawText,this.options!.context,
          `https://${this.env.BAILIAN_WORKSPACE_ID}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions`,
          { Authorization: `Bearer ${this.env.BAILIAN_API_KEY}`, "X-DashScope-WorkSpace": this.env.BAILIAN_WORKSPACE_ID },this.abort.signal,this.io.fetch),
          new Promise<never>((_,reject) => { timeout = this.timer(() => { this.abort.abort(); reject(new Error()); },15000); })]);
      } catch { cleanupFailed = true; }
      finally { if (timeout) { this.io.clearTimeout(timeout); this.timers.delete(timeout); } }
    }
    if (this.phase !== "cleanup") return;
    const billedSeconds = rawText ? Math.ceil(this.bytes/32000) : 0;
    try {
      await this.ledger.settle(this.row.user_id,this.row.id,billedSeconds,now());
      if (this.phase !== "cleanup") return;
      this.phase = "done"; this.dispose();
      this.send({ type: "completed",rawText,text,billedSeconds,cleanupFailed }); this.close(this.client);
    } catch { this.stop("settlement_failed"); }
  }
  private raw() { return [...this.segments].sort(([a],[b]) => a-b).map(([,text]) => text).join(""); }
}
