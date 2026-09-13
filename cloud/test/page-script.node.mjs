import { test } from "node:test";
import assert from "node:assert/strict";
import { Script } from "node:vm";
import { accountPage } from "../src/account-page.ts";

// Worker CSP correctly forbids runtime code evaluation. Only Node compiles the
// browser script for this syntax regression check; it never executes that code.
for (const device of [false, true]) {
  for (const enabled of [false, true]) {
    test(`inline script parses: device=${device}, enabled=${enabled}`, async () => {
      const html = await accountPage({ google: true, discord: true, email: true, enabled, device }).text();
      const script = html.match(/<script nonce="[0-9a-f]+">([\s\S]*?)<\/script>/)?.[1];
      assert.ok(script);
      assert.doesNotThrow(() => new Script(script));
    });
  }
}
