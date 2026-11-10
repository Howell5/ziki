import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { promisify } from "node:util";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";

const run = promisify(execFile);

if (process.env.ZIKI_PROXY_TEST_CHILD === "1") {
  const { Miniflare } = await import("miniflare");
  const { proxyOutbound } = await import("../scripts/dev-proxy.mjs");
  const outbound = [];
  const worker = new Miniflare({
    workers: [{
      config: {
        name: "proxy-regression",
        type: "worker",
        compatibilityDate: "2026-09-11",
        manifest: {
          mainModule: "index.js",
          modules: {
            "index.js": {
              type: "esm",
              contents: `export default { fetch(request) {
                const url = new URL(request.url);
                const target = url.pathname === "/socket"
                  ? ${JSON.stringify(process.env.ZIKI_PROXY_TEST_ECHO)}
                  : "http://ziki-proxy-test.invalid" + url.pathname + url.search;
                return fetch(target, {
                  method: request.method, headers: request.headers,
                  body: request.body, redirect: "manual"
                });
              }};`,
            },
          },
        },
      },
      dev: {
        outboundService: {
          type: "fetcher",
          handler(request) {
            outbound.push(request.url);
            return proxyOutbound(request);
          },
        },
      },
    }],
  });

  try {
    const post = await worker.dispatchFetch("http://worker.invalid/post", {
      method: "POST",
      headers: { "content-type": "application/json", "x-test-header": "forwarded" },
      body: JSON.stringify({ message: "body through workerd" }),
    });
    assert.equal(post.status, 201);
    assert.deepEqual(await post.json(), {
      method: "POST", body: '{"message":"body through workerd"}',
      contentType: "application/json", header: "forwarded",
    });

    const redirect = await worker.dispatchFetch("http://worker.invalid/redirect", { redirect: "manual" });
    assert.equal(redirect.status, 302);
    assert.equal(redirect.headers.get("location"), "http://ziki-proxy-test.invalid/followed");
    assert.equal(await redirect.text(), "redirect response");

    const errors = [];
    const originalError = console.error;
    console.error = (...args) => errors.push(args.join(" "));
    try {
      const failed = await worker.dispatchFetch("http://worker.invalid/failure?code=secret-code", {
        headers: { authorization: "Bearer secret-token", cookie: "session=secret-cookie" },
      });
      assert.equal(failed.status, 502);
      assert.equal(await failed.text(), "Upstream connection unavailable");
      assert.deepEqual(errors, ["[Ziki local proxy] Upstream connection failed or timed out."]);
    } finally {
      console.error = originalError;
    }

    const upgrade = await worker.dispatchFetch("http://worker.invalid/socket", {
      headers: { Upgrade: "websocket" },
    });
    assert.equal(upgrade.status, 101);
    const socket = upgrade.webSocket;
    assert.ok(socket);
    socket.accept();
    const echoed = new Promise((resolve, reject) => {
      socket.addEventListener("message", event => resolve(event.data), { once: true });
      socket.addEventListener("error", reject, { once: true });
    });
    socket.send("echo through workerd");
    assert.equal(await echoed, "echo through workerd");
    const closed = new Promise(resolve => socket.addEventListener("close", resolve, { once: true }));
    socket.close(1000);
    await closed;
    assert.deepEqual(outbound.map(url => new URL(url).pathname), ["/post", "/redirect", "/failure", "/echo"]);
  } finally {
    await worker.dispose();
  }
} else {
  test("Worker outbound honors the local proxy, preserves redirects, sanitizes failure, and echoes WebSockets", { timeout: 30_000 }, async t => {
    const requests = [];
    const tunnels = [];
    const proxy = createServer(async (request, response) => {
      let body = "";
      for await (const chunk of request) body += chunk;
      requests.push(request.url);
      if (request.url === "/failure?code=secret-code") {
        request.socket.destroy();
      } else if (request.url === "/redirect") {
        response.writeHead(302, { location: "http://ziki-proxy-test.invalid/followed" });
        response.end("redirect response");
      } else {
        response.writeHead(201, { "content-type": "application/json" });
        response.end(JSON.stringify({
          method: request.method, body,
          contentType: request.headers["content-type"], header: request.headers["x-test-header"],
        }));
      }
    });
    proxy.on("connect", (request, socket, head) => {
      tunnels.push(request.url);
      socket.write("HTTP/1.1 200 Connection Established\r\n\r\n");
      if (head.length) socket.unshift(head);
      proxy.emit("connection", socket);
    });
    const echo = createServer();
    const webSockets = new WebSocketServer({ server: echo });
    webSockets.on("connection", socket => socket.on("message", message => socket.send(message.toString())));
    t.after(() => {
      webSockets.close();
      proxy.closeAllConnections();
      proxy.close();
      echo.close();
    });
    proxy.listen(0, "127.0.0.1");
    echo.listen(0, "127.0.0.1");
    await Promise.all([once(proxy, "listening"), once(echo, "listening")]);

    // Proxy settings must exist before Node initializes its global dispatcher.
    const proxyURL = `http://127.0.0.1:${proxy.address().port}`;
    await run(process.execPath, ["--use-env-proxy", fileURLToPath(import.meta.url)], {
      cwd: fileURLToPath(new URL("..", import.meta.url)),
      timeout: 25_000,
      env: {
        ...process.env,
        HTTP_PROXY: proxyURL, HTTPS_PROXY: proxyURL, NO_PROXY: "127.0.0.1,localhost",
        http_proxy: proxyURL, https_proxy: proxyURL, no_proxy: "127.0.0.1,localhost",
        ZIKI_PROXY_TEST_CHILD: "1",
        ZIKI_PROXY_TEST_ECHO: `http://127.0.0.1:${echo.address().port}/echo`,
        WRANGLER_SEND_METRICS: "false",
      },
    });
    assert.deepEqual(requests, ["/post", "/redirect", "/failure?code=secret-code"]);
    assert.ok(tunnels.length > 0);
    assert.ok(tunnels.every(target => target === "ziki-proxy-test.invalid:80"));
  });
}
