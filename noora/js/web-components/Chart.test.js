// @vitest-environment happy-dom

import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";

const echarts = vi.hoisted(() => ({
  init: vi.fn(),
  registerTheme: vi.fn(),
}));

vi.mock("echarts", () => echarts);

import {
  registerNooraChart,
  registerNooraChartAxis,
  registerNooraChartCategory,
  registerNooraChartGrid,
  registerNooraChartPoint,
  registerNooraChartSeries,
} from "./Remaining.js";

beforeAll(() => {
  registerNooraChart();
  registerNooraChartAxis();
  registerNooraChartCategory();
  registerNooraChartGrid();
  registerNooraChartPoint();
  registerNooraChartSeries();
});

afterEach(() => {
  document.body.replaceChildren();
  vi.clearAllMocks();
});

describe("NooraChart", () => {
  it("initializes the drawing surface with its renderer and options", async () => {
    const instance = {
      dispose: vi.fn(),
      on: vi.fn(),
      resize: vi.fn(),
      setOption: vi.fn(),
    };
    echarts.init.mockReturnValue(instance);

    const chart = document.createElement("noora-chart");
    chart.renderer = "svg";
    const options = {
      xAxis: { type: "category", data: ["Mon", "Tue"] },
      yAxis: {},
      series: [{ type: "line", data: [2, 5] }],
    };
    chart.options = options;
    document.body.append(chart);
    await chart.updateComplete;

    const drawingSurface = chart.shadowRoot.querySelector(
      '[data-part="chart"]',
    );
    expect(echarts.registerTheme).toHaveBeenCalledWith(
      "noora",
      expect.any(Object),
    );
    expect(echarts.init).toHaveBeenCalledWith(drawingSurface, "noora", {
      renderer: "svg",
    });
    expect(chart.options).toEqual(options);
    expect(instance.setOption).toHaveBeenCalledWith(options, {
      notMerge: true,
    });

    chart.remove();

    expect(instance.dispose).toHaveBeenCalledOnce();
  });

  it("exposes options as a property without observing an options attribute", async () => {
    const instance = {
      dispose: vi.fn(),
      on: vi.fn(),
      resize: vi.fn(),
      setOption: vi.fn(),
    };
    echarts.init.mockReturnValue(instance);

    const chart = document.createElement("noora-chart");
    chart.setAttribute("options", '{"series":[{"type":"bar","data":[1]}]}');
    document.body.append(chart);
    await chart.updateComplete;

    expect(chart.options).toEqual({});
    expect(instance.setOption).toHaveBeenCalledWith({}, { notMerge: true });
  });

  it("allows navigation from an interactive point to be cancelled", async () => {
    const instance = {
      dispose: vi.fn(),
      on: vi.fn(),
      resize: vi.fn(),
      setOption: vi.fn(),
    };
    echarts.init.mockReturnValue(instance);

    const chart = document.createElement("noora-chart");
    const selection = vi.fn((event) => event.preventDefault());
    chart.addEventListener("noora-chart-select", selection);
    document.body.append(chart);
    await chart.updateComplete;

    const clickHandler = instance.on.mock.calls.find(
      ([eventName]) => eventName === "click",
    )[1];
    clickHandler({ data: { url: "/projects" } });

    expect(selection).toHaveBeenCalledOnce();
    expect(selection.mock.calls[0][0].cancelable).toBe(true);
    expect(selection.mock.calls[0][0].defaultPrevented).toBe(true);
  });

  it("applies a changed color palette without recreating the chart", async () => {
    const instance = {
      dispose: vi.fn(),
      on: vi.fn(),
      resize: vi.fn(),
      setOption: vi.fn(),
    };
    echarts.init.mockReturnValue(instance);

    const chart = document.createElement("noora-chart");
    chart.options = { colors: ["#111111"], series: [] };
    document.body.append(chart);
    await chart.updateComplete;

    chart.options = { colors: ["#222222"], series: [] };
    await chart.updateComplete;

    expect(echarts.init).toHaveBeenCalledOnce();
    expect(instance.setOption.mock.lastCall[0].color).toEqual(["#222222"]);
  });

  it("builds chart options from declarative configuration children", async () => {
    const instance = {
      dispose: vi.fn(),
      on: vi.fn(),
      resize: vi.fn(),
      setOption: vi.fn(),
    };
    echarts.init.mockReturnValue(instance);

    const chart = document.createElement("noora-chart");
    chart.tooltipTrigger = "axis";
    chart.innerHTML = `
      <noora-chart-grid contain-label height="76" width="400"></noora-chart-grid>
      <noora-chart-axis dimension="x" type="category">
        <noora-chart-category>Mon</noora-chart-category>
        <noora-chart-category>Tue</noora-chart-category>
      </noora-chart-axis>
      <noora-chart-axis
        dimension="y"
        type="value"
        min="0"
        max="100"
        label-format="{value}%"
        hide-line
        hide-ticks
        dashed-grid
      ></noora-chart-axis>
      <noora-chart-series name="Effectiveness" type="line" symbol="none">
        <noora-chart-point value="2"></noora-chart-point>
        <noora-chart-point value="5"></noora-chart-point>
      </noora-chart-series>
    `;
    document.body.append(chart);
    await Promise.all(
      [...chart.querySelectorAll("*")].map((child) => child.updateComplete),
    );
    await chart.updateComplete;

    expect(instance.setOption).toHaveBeenLastCalledWith(
      {
        colors: [
          "var:noora-chart-primary",
          "var:noora-chart-secondary",
          "var:noora-chart-tertiary",
          "var:noora-chart-quaternary",
        ],
        series: [
          {
            label: { show: false },
            name: "Effectiveness",
            stack: null,
            type: "line",
            symbol: "none",
            data: [2, 5],
          },
        ],
        yAxis: {
          type: "value",
          min: 0,
          max: 100,
          axisLabel: { fontSize: 10, formatter: "{value}%" },
          axisLine: { show: false },
          axisTick: { show: false },
          splitLine: { lineStyle: { type: "dashed" } },
        },
        xAxis: {
          type: "category",
          data: ["Mon", "Tue"],
          axisLabel: { fontSize: 10 },
          axisLine: { show: false },
          axisTick: { show: false },
          splitLine: { lineStyle: { type: "dashed" } },
        },
        tooltip: { show: true, trigger: "axis" },
        grid: { containLabel: true, height: 76, width: 400 },
        legend: { left: "center", top: "0" },
        textStyle: { fontFamily: "Geist Mono" },
      },
      { notMerge: true },
    );
  });

  it("matches the LiveView horizontal bar configuration", async () => {
    const instance = {
      dispose: vi.fn(),
      on: vi.fn(),
      resize: vi.fn(),
      setOption: vi.fn(),
    };
    echarts.init.mockReturnValue(instance);

    const chart = document.createElement("noora-chart");
    chart.innerHTML = `
      <noora-chart-grid contain-label height="76" width="400"></noora-chart-grid>
      <noora-chart-axis
        dimension="x"
        type="value"
        label-format="{value}h"
        label-size="10"
        label-margin="25"
      ></noora-chart-axis>
      <noora-chart-axis dimension="y" type="category" no-boundary-gap>
        <noora-chart-category>Selective Test</noora-chart-category>
        <noora-chart-category>Build Cache</noora-chart-category>
      </noora-chart-axis>
      <noora-chart-series type="bar" bar-gap="-100%" bar-width="24" border-radius="7">
        <noora-chart-point value="19"></noora-chart-point>
        <noora-chart-point value="22"></noora-chart-point>
      </noora-chart-series>
      <noora-chart-series type="bar" bar-width="24" border-radius="7">
        <noora-chart-point value="7.2"></noora-chart-point>
        <noora-chart-point value="9"></noora-chart-point>
      </noora-chart-series>
    `;
    document.body.append(chart);
    await Promise.all(
      [...chart.querySelectorAll("*")].map((child) => child.updateComplete),
    );
    await chart.updateComplete;

    const options = instance.setOption.mock.lastCall[0];
    expect(options).toEqual({
      colors: [
        "var:noora-chart-primary",
        "var:noora-chart-secondary",
        "var:noora-chart-tertiary",
        "var:noora-chart-quaternary",
      ],
      series: [
        {
          data: [19, 22],
          label: { show: false },
          name: "",
          type: "bar",
          stack: null,
          barGap: "-100%",
          itemStyle: { borderRadius: 7 },
          barWidth: 24,
        },
        {
          data: [7.2, 9],
          label: { show: false },
          name: "",
          type: "bar",
          stack: null,
          itemStyle: { borderRadius: 7 },
          barWidth: 24,
        },
      ],
      yAxis: {
        data: ["Selective Test", "Build Cache"],
        type: "category",
        axisLabel: { fontSize: 10 },
        splitLine: { lineStyle: { type: "dashed" } },
        boundaryGap: false,
        axisLine: { show: false },
        axisTick: { show: false },
      },
      xAxis: {
        type: "value",
        axisLabel: {
          formatter: "{value}h",
          margin: 25,
          fontSize: 10,
        },
        splitLine: { lineStyle: { type: "dashed" } },
        axisLine: { show: false },
        axisTick: { show: false },
      },
      tooltip: { show: true, trigger: "axis" },
      grid: { width: 400, height: 76, containLabel: true },
      legend: { left: "center", top: "0" },
      textStyle: { fontFamily: "Geist Mono" },
    });
  });
});
