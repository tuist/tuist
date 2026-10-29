// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import ScrollArea from "./ScrollArea.js";

const mounted = [];

function setup({ key = "sidebar", height = 200, extent = 1200 } = {}) {
  const el = document.createElement("div");
  if (key) el.dataset.scrollPersistKey = key;
  el.innerHTML =
    '<div data-part="viewport"></div><div data-part="scrollbar"><div data-part="thumb"></div></div>';
  document.body.appendChild(el);
  const viewport = el.querySelector('[data-part="viewport"]');
  const track = el.querySelector('[data-part="scrollbar"]');
  let top = 0;
  Object.defineProperties(viewport, {
    clientHeight: { get: () => height },
    scrollHeight: { get: () => extent },
    scrollTop: {
      get: () => top,
      set: (value) => {
        top = Math.max(0, Math.min(extent - height, value));
      },
    },
  });
  Object.defineProperty(track, "clientHeight", { value: 200 });
  const hook = Object.assign({ el }, ScrollArea);
  hook.mounted();
  const result = {
    el,
    viewport,
    hook,
    resize(nextExtent, nextHeight = height) {
      extent = nextExtent;
      height = nextHeight;
      hook.update();
    },
    scroll(position) {
      viewport.scrollTop = position;
      viewport.dispatchEvent(new Event("scroll"));
    },
    destroy() {
      if (!el.isConnected) return;
      hook.beforeDestroy();
      hook.destroyed();
      el.remove();
    },
  };
  mounted.push(result);
  return result;
}

beforeEach(() => sessionStorage.clear());
afterEach(() => {
  for (const area of mounted.splice(0)) area.destroy();
  vi.restoreAllMocks();
});

describe("scroll position persistence", () => {
  it("restores the position after a sidebar remount and updates the thumb", () => {
    const first = setup();
    first.scroll(620);
    first.destroy();
    const next = setup();
    expect(next.viewport.scrollTop).toBe(620);
    expect(
      next.el.querySelector('[data-part="thumb"]').style.transform,
    ).toContain("103.333");
    expect(sessionStorage.getItem("noora-scroll:sidebar")).toBe("620");
  });

  it("waits for child collapsibles without overwriting a clamped position", () => {
    sessionStorage.setItem("noora-scroll:sidebar", "800");
    const area = setup({ extent: 400 });
    area.scroll(200);
    expect(sessionStorage.getItem("noora-scroll:sidebar")).toBe("800");
    area.resize(1200);
    expect(area.viewport.scrollTop).toBe(800);
    expect(area.hook.pendingScrollTop).toBeNull();
  });

  it("lets user input cancel a pending restoration", () => {
    sessionStorage.setItem("noora-scroll:sidebar", "800");
    const area = setup({ extent: 400 });
    area.viewport.dispatchEvent(new WheelEvent("wheel", { bubbles: true }));
    area.scroll(100);
    area.resize(1200);
    expect(area.viewport.scrollTop).toBe(100);
    expect(sessionStorage.getItem("noora-scroll:sidebar")).toBe("100");
  });

  it("does not overwrite desktop state while the sidebar is hidden on mobile", () => {
    sessionStorage.setItem("noora-scroll:sidebar", "800");
    const area = setup({ height: 0 });
    area.destroy();
    expect(sessionStorage.getItem("noora-scroll:sidebar")).toBe("800");
    expect(setup().viewport.scrollTop).toBe(800);
  });

  it("keeps independent sidebar IDs and leaves ordinary scroll areas alone", () => {
    setup().scroll(400);
    expect(setup({ key: "other-sidebar" }).viewport.scrollTop).toBe(0);
    const ordinary = setup({ key: null });
    ordinary.scroll(900);
    expect(sessionStorage.getItem("noora-scroll:sidebar")).toBe("400");
  });

  it.each(["invalid", "-1", "Infinity"])(
    "ignores invalid saved positions: %s",
    (stored) => {
      sessionStorage.setItem("noora-scroll:sidebar", stored);
      expect(setup().viewport.scrollTop).toBe(0);
    },
  );

  it("continues scrolling when browser storage is unavailable", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("unavailable");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("unavailable");
    });
    const area = setup();
    expect(() => area.scroll(500)).not.toThrow();
    expect(area.viewport.scrollTop).toBe(500);
  });

  it("removes persistence listeners when the hook is destroyed", () => {
    const area = setup();
    area.scroll(100);
    area.destroy();
    sessionStorage.clear();
    area.scroll(300);
    window.dispatchEvent(new Event("pagehide"));
    expect(sessionStorage.getItem("noora-scroll:sidebar")).toBeNull();
  });
});
