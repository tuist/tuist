// Shades the hovered step or insight row's time window across every
// metric chart in the runner-job Overview, correlating CI work with
// the part of the resource graphs it produced.
//
// The charts are owned by the NooraChart hook (one ECharts instance
// each), which exposes its instance on the chart element as
// `__nooraChart`. We use that object directly rather than
// `echarts.getInstanceByDom`, because Noora bundles its own ECharts
// copy — a lookup from a different copy's module-local registry would
// never resolve the instance. We add a `markArea` band addressed by the
// step's `[start, end]` epoch-ms window, which lands precisely because
// the charts use a time x-axis. If a chart isn't ready the highlight is
// simply skipped.
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
      // Ignore moves that stay inside the same highlighted row.
      if (row.contains(event.relatedTarget)) return;
      this.clear();
    };

    this.el.addEventListener("mouseover", this.onPointerOver);
    this.el.addEventListener("mouseout", this.onPointerOut);
    // Keyboard parity: focusing a highlighted row highlights too.
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
      .map((dom) => dom.__nooraChart)
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
