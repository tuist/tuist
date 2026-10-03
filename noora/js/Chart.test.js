import { describe, it, expect } from "vitest";
import {
  prepareChartOptions,
  rangeBarTooltipFormatter,
  tooltipSeries,
} from "./Chart.js";

describe("tooltipSeries", () => {
  it("formats a value with the configured formatter", () => {
    const html = tooltipSeries(
      { color: "#000", seriesName: "p50", value: [1, 1500] },
      { valueFormat: "fn:formatMilliseconds" },
    );

    expect(html).toContain("1.5s");
  });

  it("renders a missing value as no data rather than as zero", () => {
    const html = tooltipSeries(
      { color: "#000", seriesName: "p50", value: [1, null] },
      { valueFormat: "fn:formatMilliseconds" },
    );

    expect(html).not.toContain("0ms");
    expect(html).toContain("—");
  });
});

describe("range bars", () => {
  const chartElement = { setAttribute: () => {} };

  it("replaces range-bar callbacks and supplies the required axes and encoding", () => {
    const option = prepareChartOptions(
      {
        tooltip: { formatter: "fn:rangeBarTooltip" },
        xAxis: { type: "category" },
        yAxis: { type: "value" },
        series: [{ type: "custom", renderItem: "fn:rangeBar" }],
      },
      chartElement,
    );

    expect(option.tooltip.formatter).toBe(rangeBarTooltipFormatter);
    expect(option.tooltip.trigger).toBe("item");
    expect(option.series[0].renderItem).toBeTypeOf("function");
    expect(option.series[0].encode).toEqual({ x: [1, 2], y: 0 });
    expect(option.xAxis.type).toBe("value");
    expect(option.yAxis.type).toBe("category");
  });

  it("moves component labels to the range-bar category axis", () => {
    const option = prepareChartOptions(
      {
        xAxis: { type: "category", data: ["Worker 1"] },
        yAxis: { type: "value" },
        series: [{ type: "custom", renderItem: "fn:rangeBar" }],
      },
      chartElement,
    );

    expect(option.xAxis.data).toBeUndefined();
    expect(option.yAxis.data).toEqual(["Worker 1"]);
  });

  it("preserves secondary axes while configuring the range-bar axes", () => {
    const option = prepareChartOptions(
      {
        xAxis: [
          { type: "category", data: ["Worker 1"] },
          { type: "value", name: "Secondary time" },
        ],
        yAxis: [{ type: "value" }, { type: "value", name: "Cumulative work" }],
        series: [{ type: "custom", renderItem: "fn:rangeBar" }],
      },
      chartElement,
    );

    expect(option.xAxis).toHaveLength(2);
    expect(option.xAxis[1].name).toBe("Secondary time");
    expect(option.yAxis).toHaveLength(2);
    expect(option.yAxis[1].name).toBe("Cumulative work");
    expect(option.yAxis[0].data).toEqual(["Worker 1"]);
  });

  it("preserves an explicitly configured tooltip trigger and encoding", () => {
    const option = prepareChartOptions(
      {
        tooltip: { trigger: "axis", formatter: "fn:rangeBarTooltip" },
        series: [
          {
            type: "custom",
            renderItem: "fn:rangeBar",
            encode: { x: [2, 1], y: 0 },
          },
        ],
      },
      chartElement,
    );

    expect(option.tooltip.trigger).toBe("axis");
    expect(option.series[0].encode).toEqual({ x: [2, 1], y: 0 });
  });

  it("formats an axis-trigger parameter and escapes caller-provided labels", () => {
    const html = rangeBarTooltipFormatter([
      {
        name: "fallback",
        value: [0, 250, 1750],
        data: {
          name: "<Compile>",
          durationLabel: "Execution & analysis",
          startLabel: 'Worker "1"',
        },
      },
    ]);

    expect(html).toContain("&lt;Compile&gt;");
    expect(html).toContain("Execution &amp; analysis");
    expect(html).toContain("Worker &quot;1&quot;");
    expect(html).toContain("1.5s");
    expect(html).toContain("250ms");
    expect(html).toContain('data-part="series-item"');
    expect(html).not.toContain("<Compile>");
  });

  it("renders missing timing values as unavailable without inventing labels", () => {
    const html = rangeBarTooltipFormatter({
      value: [0, null, undefined],
      data: {
        name: "Pending",
        durationLabel: "Execution",
        startLabel: "Worker 1",
      },
    });

    expect(html).toContain("—");
    expect(html).not.toContain("NaN");
    expect(html).not.toContain("Build activity");
    expect(html).not.toContain("Other");
    expect(html).not.toContain("starts");
  });

  it("omits ambiguous values when tooltip labels are not supplied", () => {
    const html = rangeBarTooltipFormatter({
      value: [0, 100, 300],
      data: { name: "Task" },
    });

    expect(html).toContain("Task");
    expect(html).not.toContain("100ms");
    expect(html).not.toContain("200ms");
  });

  it("does not render an empty tooltip for an unlabeled data point", () => {
    const html = rangeBarTooltipFormatter({
      value: [0, 100, 300],
      data: [0, 100, 300],
    });

    expect(html).toBe("");
  });

  it("does not render a range bar with invalid dimensions", () => {
    const option = prepareChartOptions(
      { series: [{ type: "custom", renderItem: "fn:rangeBar" }] },
      chartElement,
    );

    const api = {
      value: () => undefined,
    };

    expect(option.series[0].renderItem({}, api)).toBeNull();
  });

  it("uses the start and end dimensions to render the range geometry", () => {
    const option = prepareChartOptions(
      { series: [{ type: "custom", renderItem: "fn:rangeBar" }] },
      chartElement,
    );
    const api = {
      value: (dimension) => [1, 200, 700][dimension],
      coord: ([x, y]) => [x * 0.5, 100 + y * 40],
      size: () => [0, 40],
      style: () => ({ fill: "#000" }),
    };
    const params = {
      coordSys: { x: 0, y: 0, width: 800, height: 300 },
    };

    const result = option.series[0].renderItem(params, api);

    expect(result.shape.x).toBe(100);
    expect(result.shape.width).toBe(250);
  });
});

describe("large counts", () => {
  it.each([{}, { valueFormat: "{value}" }, { valueFormat: "fn:formatNumber" }])(
    "humanizes tooltip counts with %j",
    (options) => {
      expect(
        tooltipSeries(
          { color: "#000", seriesName: "Cold", value: [1, 121755] },
          options,
        ),
      ).toContain("121.8K");
      expect(
        tooltipSeries(
          { color: "#000", seriesName: "Evicted", value: 836 },
          options,
        ),
      ).toContain("836");
    },
  );

  it("humanizes count axes while preserving units and category labels", () => {
    const option = prepareChartOptions({
      xAxis: { type: "category", data: [20260911] },
      yAxis: [
        { type: "value" },
        { axisLabel: { formatter: "{value}" } },
        { axisLabel: { formatter: "{value}%" } },
        { type: "time" },
      ],
    });
    expect(option.yAxis[0].axisLabel.formatter(300000)).toBe("300K");
    expect(option.yAxis[1].axisLabel.formatter(2901412)).toBe("2.9M");
    expect(option.yAxis[2].axisLabel.formatter).toBe("{value}%");
    expect(option.yAxis[3].axisLabel).toBeUndefined();
    expect(option.xAxis.axisLabel).toBeUndefined();
  });

  it("keeps explicit tooltip units", () => {
    expect(
      tooltipSeries(
        { value: 121755 },
        { valueFormat: "fn:formatMilliseconds" },
      ),
    ).toContain("2m 1s");
    expect(tooltipSeries({ value: 95 }, { valueFormat: "{value}%" })).toContain(
      "95%",
    );
  });
});
