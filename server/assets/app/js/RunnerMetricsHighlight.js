import * as echarts from "echarts";

// Shades the hovered step's time window across every metric chart in
// the runner-job Overview, correlating a CI step with the part of the
// resource graphs it produced.
//
// The charts are owned by the NooraChart hook (one ECharts instance
// each); we reach them via `echarts.getInstanceByDom` and add a
// `markArea` band addressed by the step's `[start, end]` epoch-ms
// window — which lands precisely because the charts use a time
// x-axis. If the instance can't be resolved (e.g. a charts-less
// render) the highlight is simply skipped.
// The band colour comes from Noora's overlay token so it tracks the
// theme (incl. light/dark) instead of being hardcoded. Reading the
// custom property directly yields the unresolved `light-dark(var(…))`
// expression, so we set it on a throwaway element and read back the
// browser-resolved colour ECharts can render.
function resolveHighlightColor(host) {
  const probe = document.createElement("span");
  probe.style.color = "var(--noora-surface-overlay)";
  probe.style.display = "none";
  host.appendChild(probe);
  const color = getComputedStyle(probe).color;
  probe.remove();
  return color;
}

export default {
  mounted() {
    this.onPointerOver = (event) => {
      const row = event.target.closest("[data-step-start]");
      if (!row || !this.el.contains(row)) return;
      this.highlight(row.dataset.stepStart, row.dataset.stepEnd);
    };

    this.onPointerOut = (event) => {
      const row = event.target.closest("[data-step-start]");
      if (!row || !this.el.contains(row)) return;
      // Ignore moves that stay inside the same step row.
      if (row.contains(event.relatedTarget)) return;
      this.clear();
    };

    this.el.addEventListener("mouseover", this.onPointerOver);
    this.el.addEventListener("mouseout", this.onPointerOut);
    // Keyboard parity: focusing a step row highlights too.
    this.el.addEventListener("focusin", this.onPointerOver);
    this.el.addEventListener("focusout", this.onPointerOut);
  },

  destroyed() {
    this.el.removeEventListener("mouseover", this.onPointerOver);
    this.el.removeEventListener("mouseout", this.onPointerOut);
    this.el.removeEventListener("focusin", this.onPointerOver);
    this.el.removeEventListener("focusout", this.onPointerOut);
  },

  charts() {
    return Array.from(this.el.querySelectorAll("[data-metrics-charts] [data-part='chart']"))
      .map((dom) => echarts.getInstanceByDom(dom))
      .filter(Boolean);
  },

  highlight(start, end) {
    const startMs = Number(start);
    const endMs = Number(end);
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs)) return;

    const markArea = {
      silent: true,
      itemStyle: { color: resolveHighlightColor(this.el) },
      data: [[{ xAxis: startMs }, { xAxis: endMs }]],
    };

    this.charts().forEach((chart) => {
      // markArea attaches to a series; series 0 always exists and one
      // band covers the whole plot regardless of series count.
      chart.setOption({ series: [{ markArea }] }, { lazyUpdate: true });
    });
  },

  clear() {
    this.charts().forEach((chart) => {
      chart.setOption({ series: [{ markArea: { data: [] } }] }, { lazyUpdate: true });
    });
  },
};
