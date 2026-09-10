// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as echarts from "echarts";
import Chart from "./Chart.js";

vi.mock("echarts", () => ({
  registerTheme: vi.fn(),
  init: vi.fn(() => ({
    setOption: vi.fn(),
    on: vi.fn(),
    resize: vi.fn(),
    dispose: vi.fn(),
  })),
}));

describe("chart lifecycle", () => {
  let hooks;
  let observers;

  beforeEach(() => {
    hooks = [];
    observers = [];
    vi.clearAllMocks();
    vi.stubGlobal(
      "IntersectionObserver",
      class {
        constructor(callback) {
          this.callback = callback;
          this.observe = vi.fn();
          this.disconnect = vi.fn();
          observers.push(this);
        }
      },
    );
  });

  afterEach(() => {
    for (const hook of hooks) hook.destroyed();
    document.body.innerHTML = "";
    vi.unstubAllGlobals();
  });

  function mount({ lazy = false } = {}) {
    const el = document.createElement("div");
    el.dataset.lazy = String(lazy);
    el.innerHTML = `<div data-part="chart"></div>`;
    document.body.appendChild(el);
    const hook = {
      ...Chart,
      el,
      option: vi.fn(() => ({ colors: ["#000000"], series: [] })),
    };
    hooks.push(hook);
    hook.mounted();
    return hook;
  }

  it("defers offscreen charts and renders the latest data when they approach the viewport", () => {
    const hook = mount({ lazy: true });
    const observer = observers[0];
    expect(observer.observe).toHaveBeenCalledWith(hook.el);
    expect(echarts.init).not.toHaveBeenCalled();

    hook.updated();
    window.dispatchEvent(new Event("changed-preferred-theme"));
    observer.callback([{ isIntersecting: false }]);
    expect(hook.option).not.toHaveBeenCalled();

    const latest = { colors: ["#ffffff"], series: [{ data: [42] }] };
    hook.option.mockReturnValue(latest);
    observer.callback([{ isIntersecting: true }]);
    expect(hook.chart.setOption).toHaveBeenCalledWith(latest);
    expect(observer.disconnect).toHaveBeenCalledOnce();
    observer.callback([{ isIntersecting: true }]);
    expect(echarts.init).toHaveBeenCalledOnce();
  });

  it("does not initialize a lazy chart destroyed before it becomes visible", () => {
    const hook = mount({ lazy: true });
    const observer = observers[0];
    hook.destroyed();
    observer.callback([{ isIntersecting: true }]);
    expect(observer.disconnect).toHaveBeenCalledOnce();
    expect(echarts.init).not.toHaveBeenCalled();
  });

  it("keeps existing charts eager and falls back when observation is unavailable", () => {
    mount();
    expect(echarts.init).toHaveBeenCalledOnce();
    expect(observers).toHaveLength(0);

    vi.stubGlobal("IntersectionObserver", undefined);
    mount({ lazy: true });
    expect(echarts.init).toHaveBeenCalledTimes(2);
  });

  it("keeps one resize listener through updates and removes it on destruction", () => {
    const hook = mount();
    const initialChart = hook.chart;
    hook.updated();
    hook.updated();
    expect(initialChart.dispose).toHaveBeenCalledOnce();
    expect(hook.chart.setOption.mock.calls[0][0].animation).toBe(false);

    window.dispatchEvent(new Event("resize"));
    window.dispatchEvent(new Event("phx:resize"));
    expect(hook.chart.resize).toHaveBeenCalledTimes(2);

    hook.destroyed();
    window.dispatchEvent(new Event("resize"));
    window.dispatchEvent(new Event("phx:resize"));
    expect(hook.chart.resize).toHaveBeenCalledTimes(2);
    expect(
      hook.el.querySelector("[data-part='chart']").__nooraChart,
    ).toBeNull();
  });
});
