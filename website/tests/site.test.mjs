import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { copy, release } from "../src/content.ts";

test("English and Chinese have matching content structure", () => {
  function shape(value) {
    if (Array.isArray(value)) return value.map(shape);
    if (value && typeof value === "object")
      return Object.fromEntries(
        Object.entries(value).map(([key, entry]) => [key, shape(entry)]),
      );
    assert.equal(typeof value, "string");
    assert.ok(value.trim().length > 0);
    return "text";
  }
  assert.deepEqual(shape(copy.en), shape(copy.zh));
});

test("download is a pinned official arm64 DMG", () => {
  const url = new URL(release.download);
  assert.equal(url.protocol, "https:");
  assert.equal(url.hostname, "github.com");
  assert.equal(
    url.pathname,
    `/Howell5/ziki/releases/download/v${release.version}/Ziki-${release.version}-macOS-arm64.dmg`,
  );
  assert.ok(copy.en.preview.includes(release.version));
  assert.ok(copy.zh.preview.includes(release.version));
});

test("list and prose scenarios remain distinct in both languages", () => {
  for (const c of Object.values(copy)) {
    assert.equal(c.examples[0].result.length, 3);
    assert.equal(c.examples[1].result.length, 1);
  }
});

for (const [language, file, lang] of [
  ["en", "index.html", "en"],
  ["zh", "zh/index.html", "zh-CN"],
]) {
  test(`${language} route contains full, localized HTML without a server`, () => {
    const html = readFileSync(
      new URL(`../dist/client/${file}`, import.meta.url),
      "utf8",
    );
    assert.match(html, new RegExp(`<html[^>]+lang="${lang}"`));
    assert.ok(html.includes(copy[language].headline[0]));
    assert.ok(html.includes(copy[language].faqs[0].question));
    assert.ok(html.includes(copy[language].preview));
    assert.ok(html.includes(release.download));
    assert.match(html, /<h1[^>]*>/);
    assert.equal((html.match(/<h1\b/g) || []).length, 1);
    for (const source of html.matchAll(
      /(?:src|href)="(\/(?:assets\/|[^"\/]+\.(?:png|webp))[^"?#]*)"/g,
    )) {
      assert.ok(
        existsSync(new URL(`../dist/client${source[1]}`, import.meta.url)),
        `Missing asset: ${source[1]}`,
      );
    }
    assert.doesNotMatch(
      html,
      /fonts\.googleapis\.com|googletagmanager|google-analytics/,
    );
  });
}
