import { expect, open, test } from "nsh/test";

test("decisions only answer on press and send an option ID, not display text", async () => {
  const app = await open("./Decision.tsx", {
    width: 320, height: 240,
    host: { handlers: { answer: null } },
  });
  expect(app.host.calls()).toEqual([]);
  expect(app.texts()).toContain("Investigate cache misses, including changes to build settings and dependencies that invalidate otherwise reusable targets");
  await app.press("Compare build timings");
  expect(app.host.calls()).toEqual([{ name: "answer", data: "timing" }]);
  await app.setViewport(320, 160);
  await app.scroll("How should we investigate the slow builds?", 600);
  await app.press("Leave the investigation for later");
  expect(app.host.calls()).toEqual([
    { name: "answer", data: "timing" },
    { name: "answer", data: "later" },
  ]);
});

test("generic actions remain composer replies", async () => {
  const app = await open("./App.tsx", { host: { handlers: { reply: null } } });
  expect(app.host.calls()).toEqual([]);
  await app.press("Ask why TuistKit misses");
  expect(app.host.calls()).toEqual([{ name: "reply", data: "Why does TuistKit miss the cache so often?" }]);
});
