import test from "node:test";
import assert from "node:assert/strict";
import {
  normalizeEvents,
  matchesEvent,
  timelineDuration,
  neighborEvent,
  layoutEvents,
  clampRange,
  zoomRange,
  cursorTime,
  cursorTimeLabel,
  scrollGeometry,
  scrollStart,
} from "./BuildTimelineModel.mjs";

const event = (id, start, duration, project = "App") => ({
  event_id: id,
  start_ms: start,
  duration_ms: duration,
  project,
  target: "Core",
  category: "swiftCompilation",
});

test("Bazel action mnemonics map to the legend while setup work keeps its Other category", () => {
  const categories = [
    "CppCompile",
    "CppLink",
    "Genrule",
    "Rustc",
    "CppArchive",
    "CargoBuildScriptRun",
    "general information",
    "bazel module processing",
    "SymlinkTree",
  ];
  const events = normalizeEvents(categories.map((category, id) => ({ ...event(id, id, 1), category })));
  assert.deepEqual(
    events.map((event) => event.kind),
    ["compile", "link", "script", "compile", "link", "script", "other", "other", "other"],
  );
  assert.deepEqual(
    events.map((event) => event.category),
    categories,
  );
});

test("Bazel separates file preparation, fetching and analysis without relabeling mixed execution spans", () => {
  const categories = [
    "FileWrite",
    "Symlink",
    "SymlinkTree",
    "RunfilesTree",
    "RepoMappingManifest",
    "CppModuleMap",
    "MaterializeIncludeDir",
    "Fetching repository",
    "Remote execution download time",
    "bazel module processing",
    "package creation",
    "Starlark user function call",
    "general information",
    "Remote execution upload time",
    "CustomAction",
  ];
  const events = categories.map((category, id) => ({ ...event(id, id, 1), category }));
  assert.deepEqual(
    normalizeEvents(events, "bazel").map((event) => event.kind),
    [
      "resource",
      "resource",
      "resource",
      "resource",
      "resource",
      "resource",
      "resource",
      "fetch",
      "fetch",
      "setup",
      "setup",
      "setup",
      "other",
      "other",
      "other",
    ],
  );
  assert.equal(normalizeEvents([{ ...event(1, 0, 1), category: "configuration" }], "xcode")[0].kind, "other");
});

test("Gradle separates configuration, transforms, testing and packaging while retaining task types", () => {
  const categories = [
    "configuration",
    "transform",
    "org.gradle.api.tasks.compile.JavaCompile",
    "org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile",
    "org.gradle.api.tasks.testing.Test",
    "org.gradle.api.tasks.bundling.Jar",
    "org.gradle.api.tasks.bundling.Zip_Decorated",
    "org.gradle.api.tasks.Exec",
    "org.gradle.language.jvm.tasks.ProcessResources",
    "org.gradle.nativeplatform.tasks.LinkSharedLibrary",
    "org.gradle.api.DefaultTask",
    "org.gradle.api.tasks.Delete",
  ];
  const events = normalizeEvents(
    categories.map((category, id) => ({ ...event(id, id, 1), category })),
    "gradle",
  );
  assert.deepEqual(
    events.map((event) => event.kind),
    [
      "setup",
      "transform",
      "compile",
      "compile",
      "test",
      "package",
      "package",
      "script",
      "resource",
      "link",
      "other",
      "other",
    ],
  );
  assert.deepEqual(
    events.map((event) => event.category),
    categories,
  );
});

test("group filters intersect category-aware search and preserve failed action types", () => {
  const step = {
    title: "Creating tree",
    target: "//:app",
    project: "kura",
    kind: "resource",
    category: "SymlinkTree",
    status: "failure",
  };
  const labels = { resource: "File preparation" };
  assert.ok(matchesEvent(step, "SYMLINKTREE", "resource", labels));
  assert.ok(matchesEvent(step, "file preparation", "resource", labels));
  assert.ok(matchesEvent(step, "//:app", "failure", labels));
  assert.ok(!matchesEvent(step, "SymlinkTree", "compile", labels));
  assert.ok(!matchesEvent(step, "SymlinkTree", null, labels, false));
  assert.ok(!matchesEvent({ ...step, status: "success" }, "", "failure", labels));
});

test("profile timelines use their own duration instead of the longer BEP invocation clock", () => {
  const events = normalizeEvents([event(1, 0, 11_292.777)]);
  assert.equal(timelineDuration({ time_origin: "profile_start", duration: 11_292.777 }, events, "14200"), 11_292.777);
  assert.equal(timelineDuration({ duration: 11_292.777 }, events, "14200"), 14_200);
  assert.equal(timelineDuration({ time_origin: "profile_start", duration: 10_000 }, events, "14200"), 11_292.777);
});

test("overlapping work gets separate lanes, touching intervals reuse a lane", () => {
  const events = normalizeEvents([event(3, 10, 5), event(2, 2, 5), event(1, 0, 10)]);
  const { lanes } = layoutEvents(events);
  assert.equal(lanes, 2);
  assert.notEqual(events[0].y, events[1].y);
  assert.equal(events[2].y, events[0].y);
});

test("execution lanes reuse space across targets without losing project identity", () => {
  const events = normalizeEvents([event(1, 0, 10), event(2, 10, 10, "Tools")]);
  const layout = layoutEvents(events);
  assert.equal(layout.lanes, 1);
  assert.equal(events[0].y, events[1].y);
  assert.deepEqual(
    layout.events.map((e) => e.project),
    ["App", "Tools"],
  );
});

test("zoom excludes inactive work and compacts remaining lanes without clipping recorded timings", () => {
  const events = normalizeEvents([event(1, 0, 10), event(2, 3, 20), event(3, 20, 10)]);
  assert.equal(layoutEvents(events).lanes, 2);
  const layout = layoutEvents(events, { start: 11, span: 5 });
  assert.equal(layout.lanes, 1);
  assert.deepEqual(
    layout.events.map((e) => e.event_id),
    [2],
  );
  assert.equal(layout.events[0].y, 8);
  assert.equal(layout.events[0].start_ms, 3);
  assert.equal(layout.events[0].duration_ms, 20);
  assert.equal(layoutEvents(events, { start: 30, span: 10 }).events.length, 0);
});

test("bad intervals are excluded without manufacturing timings", () => {
  const events = normalizeEvents([
    event(1, -1, 5),
    event(2, 0, 0),
    event(3, NaN, 5),
    event(4, 0, Infinity),
    event(5, 1, 0.5),
  ]);
  assert.deepEqual(
    events.map((e) => e.event_id),
    [5],
  );
  assert.equal(events[0].end, 1.5);
});

test("zoom and pan stay within the build including sub-millisecond recordings", () => {
  assert.deepEqual(clampRange(-20, 200, 100), { start: 0, span: 100 });
  assert.deepEqual(clampRange(90, 20, 100), { start: 80, span: 20 });
  assert.deepEqual(clampRange(0, 0, 0.5), { start: 0, span: 0.5 });
});

test("pinch zoom preserves the time beneath the pointer, including at the zoom limit", () => {
  const initial = { start: 20, span: 40 };
  const zoomed = zoomRange(initial, 0.5, 0.75, 100);
  assert.deepEqual(zoomed, { start: 35, span: 20 });
  assert.deepEqual(zoomRange(zoomed, 2, 0.75, 100), initial);
  assert.deepEqual(zoomRange({ start: 40, span: 1 }, 0.5, 0.75, 100), { start: 40, span: 1 });
  assert.deepEqual(zoomRange(initial, 100, 0.75, 100), { start: 0, span: 100 });
});

test("50,000 simultaneous steps retain every interval without lane collisions", () => {
  const events = normalizeEvents(Array.from({ length: 50_000 }, (_, i) => event(i, 0, i + 1)));
  layoutEvents(events);
  assert.equal(new Set(events.map((e) => e.y)).size, 50_000);
});

test("cursor time follows the visible interval and clamps to the plot edges", () => {
  const range = { start: 5000, span: 4000 };
  assert.equal(cursorTime(12, 424, range), 5000);
  assert.equal(cursorTime(212, 424, range), 7000);
  assert.equal(cursorTime(500, 424, range), 9000);
  assert.equal(cursorTime(-10, 424, range), 5000);
  assert.equal(cursorTime(112, 224, range), 7000);
  assert.equal(cursorTimeLabel(6875), "6 s 875 ms");
  assert.equal(cursorTimeLabel(999.8), "1 s 000 ms");
});

test("horizontal overflow exists only when zoomed, with scroll positions spanning the entire build", () => {
  assert.deepEqual(scrollGeometry(424, { start: 0, span: 100 }, 100), { width: 424, left: 0 });
  const range = { start: 25, span: 50 };
  const geometry = scrollGeometry(424, range, 100);
  assert.deepEqual(geometry, { width: 824, left: 200 });
  assert.equal(scrollStart(geometry.left, geometry.width - 424, range, 100), 25);
  assert.equal(scrollStart(0, 400, range, 100), 0);
  assert.equal(scrollStart(400, 400, range, 100), 50);
  assert.equal(scrollStart(500, 400, range, 100), 50);
});

test("deep zoom remains scrollable within browser layout limits", () => {
  const range = { start: 3_600_000, span: 1 };
  const geometry = scrollGeometry(1000, range, 7_200_000);
  assert.equal(geometry.width, 8_001_000);
  assert.equal(scrollStart(geometry.left, geometry.width - 1000, range, 7_200_000), range.start);
});

test("opaque operation IDs sort stably and local keyboard navigation respects filtered steps", () => {
  const events = normalizeEvents([event("task:b", 10, 5), event("task:a", 10, 5), event("configuration:a", 0, 10)]);
  assert.deepEqual(
    events.map((e) => e.event_id),
    ["configuration:a", "task:a", "task:b"],
  );
  const filtered = events.filter((e) => e.event_id.startsWith("task:"));
  assert.equal(neighborEvent(filtered, null, "next").event_id, "task:a");
  assert.equal(neighborEvent(filtered, "task:a", "next").event_id, "task:b");
  assert.equal(neighborEvent(filtered, "task:b", "previous").event_id, "task:a");
  assert.equal(neighborEvent(filtered, null, "last").event_id, "task:b");
  assert.equal(neighborEvent(filtered, "task:b", "next"), undefined);
  assert.equal(neighborEvent([], null, "next"), undefined);
});
