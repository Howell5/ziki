import { fetch as localFetch } from "miniflare";
import { unstable_startWorker } from "wrangler";

// workerd's direct sockets ignore HTTP(S)_PROXY; retain Miniflare's WebSocket upgrade support.
export async function proxyOutbound(request) {
  try {
    return await localFetch(request.url, {
      method: request.method,
      headers: request.headers,
      body: request.body,
      redirect: "manual",
      duplex: "half",
      signal: request.headers.get("upgrade") === "websocket"
        ? request.signal
        : AbortSignal.any([request.signal, AbortSignal.timeout(15_000)]),
    });
  } catch {
    // Never log OAuth codes, cookies, provider credentials or upstream response bodies.
    console.error("[Ziki local proxy] Upstream connection failed or timed out.");
    return new Response("Upstream connection unavailable", { status: 502 });
  }
}

if (import.meta.main) {
  const worker = await unstable_startWorker({
    config: "wrangler.jsonc",
    dev: {
      remote: false,
      server: { hostname: "127.0.0.1" },
      logLevel: "error",
      outboundService: proxyOutbound,
    },
  });
  console.log(`Ziki local proxy ready: ${(await worker.url).origin}/account`);
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.once(signal, async () => { await worker.dispose(); process.exit(0); });
  }
}
