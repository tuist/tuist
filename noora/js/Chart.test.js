import { describe, it, expect } from "vitest";
import { tooltipSeries } from "./Chart.js";

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
