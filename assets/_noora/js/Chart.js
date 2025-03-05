import * as echarts from "echarts";

const formatValue = (value) => {
  if (Array.isArray(value) && value.length > 0) {
    return value[value.length - 1];
  }

  if (value !== null && typeof value === "object" && "value" in value) {
    return value.value;
  }

  return value;
};

const tooltipSeries = ({ color, name, value }) => {
  const displayValue = formatValue(value);

  return `
  <div data-part="series-item">
    <span data-part="dot" style="--color: ${Array.isArray(color) ? color[0] : color}"></span>
    <span data-part="label">${name}</span>
    <span data-part="value">${displayValue}</span>
  </div>
  `;
};

const tooltipFormatter = (params) => {
  const content = Array.isArray(params) ? params.map(tooltipSeries).join("") : tooltipSeries(params);
  return `<div class="noora-chart-tooltip">${content}</div>`;
};

const theme = {
  tooltip: {
    trigger: "item",
    appendTo: "body",
    // Reset all existing styling
    backgroundColor: "transparent",
    borderColor: "transparent",
    padding: 0,
    extraCssText: "box-shadow: none",
    textStyle: {
      fontFamily: "Inter",
    },
    // Apply our custom tooltip
    formatter: tooltipFormatter,
  },
};

export default {
  mounted() {
    echarts.registerTheme("noora", theme);
    this.chart = echarts.init(this.el, "noora", { renderer: "svg" });
    this.chart.setOption(this.option());

    window.addEventListener("resize", () => {
      this.chart.resize();
    });
  },
  updated() {
    this.chart.setOption(this.option());
  },
  destroyed() {
    this.chart.dispose();
  },
  option() {
    let option = {};
    try {
      option = JSON.parse(this.el.querySelector("[data-part='data']").textContent);
    } catch (err) {
      console.error("Failed to parse ECharts options:", err);
    }

    return option;
  },
};
