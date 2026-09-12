import assert from "node:assert/strict";

// Run inside Ego Browser, passing a page from the task's existing TaskSpace.
export async function verifyDemos(page, origin) {
  const phases = () =>
    page.evaluate(() =>
      [...document.querySelectorAll(".demo-shell")].map((e) =>
        Number(e.dataset.phase),
      ),
    );
  const scrollToCard = (index) =>
    page.evaluate(
      (index) =>
        document
          .querySelectorAll(".demo-shell")
          [index].scrollIntoView({ block: "center", behavior: "instant" }),
      index,
    );
  const waitPhase = async (index, phase) => {
    console.log(`Waiting for demo ${index + 1}, phase ${phase}`);
    await page.waitForFunction(
      ({ index, phase }) =>
        Number(
          document.querySelectorAll(".demo-shell")[index].dataset.phase,
        ) === phase,
      { index, phase },
      { timeout: 12000 },
    );
  };
  const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  await page.cdp("Emulation.setDeviceMetricsOverride", {
    width: 390,
    height: 844,
    deviceScaleFactor: 1,
    mobile: true,
  });
  await page.cdp("Emulation.setEmulatedMedia", {
    features: [{ name: "prefers-reduced-motion", value: "no-preference" }],
  });
  await page.goto(`${origin}/zh/`);
  await page.waitForFunction(
    () => document.querySelectorAll(".demo-shell").length === 2,
  );
  assert.deepEqual(await phases(), [0, 0], "off-screen demos must not start");
  await scrollToCard(0);
  await waitPhase(0, 1);
  const height = await page.evaluate(
    () => document.querySelector(".demo-shell").getBoundingClientRect().height,
  );
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
  await page.waitForFunction(
    () => document.querySelector(".demo-shell").dataset.playing === "false",
  );
  const paused = await phases();
  await delay(3200);
  assert.deepEqual(await phases(), paused, "off-screen timers must stop");
  await scrollToCard(0);
  await waitPhase(0, 3);
  assert.equal(
    await page.evaluate(
      () =>
        document.querySelector(".demo-shell").getBoundingClientRect().height,
    ),
    height,
    "output reveal must not move the card",
  );
  assert.equal((await phases())[1], 0, "second example has its own trigger");
  await scrollToCard(1);
  await waitPhase(1, 1);
  await waitPhase(1, 3);
  await scrollToCard(0);
  await delay(4500);
  assert.deepEqual(
    await phases(),
    [3, 3],
    "finished examples must not loop on re-entry",
  );
  await page.snapshot();
  await page.click(".demo-shell:first-child .demo-play");
  await waitPhase(0, 1);
  await page.click(".demo-shell:first-child .demo-play");
  await waitPhase(0, 3);

  await page.cdp("Emulation.setEmulatedMedia", {
    features: [{ name: "prefers-reduced-motion", value: "reduce" }],
  });
  await page.reload();
  await scrollToCard(1);
  await waitPhase(1, 3);
  assert.equal(
    await page.evaluate(
      () => document.querySelectorAll(".waveform.is-listening").length,
    ),
    0,
  );
  await page.cdp("Emulation.setEmulatedMedia", {
    features: [{ name: "prefers-reduced-motion", value: "no-preference" }],
  });

  const layouts = [];
  for (const path of ["/", "/zh/"]) {
    for (const [width, height] of [
      [320, 740],
      [390, 844],
      [844, 390],
      [1440, 1000],
    ]) {
      await page.cdp("Emulation.setDeviceMetricsOverride", {
        width,
        height,
        deviceScaleFactor: 1,
        mobile: width < 1000,
      });
      await page.goto(`${origin}${path}`);
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all(
          [...document.images].filter((i) => i.loading !== "lazy").map((i) => i.decode().catch(() => {})),
        );
      });
      const layout = await page.evaluate(() => ({
        width: innerWidth,
        scrollWidth: document.documentElement.scrollWidth,
        broken: [...document.images].filter((i) => i.complete && i.naturalWidth === 0).length,
        cards: document.querySelectorAll(".demo-shell").length,
      }));
      assert.equal(
        layout.scrollWidth,
        layout.width,
        `${path} at ${width}px must not overflow`,
      );
      assert.equal(layout.broken, 0);
      assert.equal(layout.cards, 2);
      layouts.push({ path, ...layout });
    }
  }
  return {
    autoplay: "passed",
    independentTriggers: "passed",
    pauseOffscreen: "passed",
    noLoop: "passed",
    replayAndStop: "passed",
    stableCardHeight: "passed",
    reducedMotion: "passed",
    layouts,
  };
}
