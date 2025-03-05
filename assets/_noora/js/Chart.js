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

const formatters = {
  firstAndLastDate: (el) => (value, index) => {
    // When there's more than one label per ~65px, ECharts automatically omits labels in the center.
    const maxLabelCount = Math.ceil(el.getBoundingClientRect().width / 65);
    const largestSeriesCount = parseInt(el.dataset.largestSeriesCount);

    // The number of labels ECharts will try to render is the smaller of the biggest number of elements in a series, or the number of labels
    // which will fit in the chart.
    const boundary = (largestSeriesCount < maxLabelCount ? largestSeriesCount : maxLabelCount) + 1;

    // Render the second label as first one, so the label itself isn't weirdly positioned under the y-axis labels. Render the last label
    // normally with `showMaxLabel` set since we have space to the right.
    if (index === 1 || index === boundary) {
      const date = new Date(value);
      return date.toLocaleDateString("en-GB", { day: "numeric", month: "short" });
    }

    return "";
  },
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
    formatter: tooltipFormatter,
  },
};

export default {
  mounted() {
    echarts.registerTheme("noora", theme);
    this.chart = echarts.init(this.el.querySelector("[data-part='chart']"), "noora", { renderer: "canvas" });
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

      if (option.series && Array.isArray(option.series)) {
        let largestSeriesCount = 0;

        option.series.forEach((series) => {
          if (series.data && Array.isArray(series.data)) {
            const itemCount = series.data.length;
            largestSeriesCount = Math.max(largestSeriesCount, itemCount);
          }
        });

        if (largestSeriesCount > 0) {
          this.el.setAttribute("data-largest-series-count", largestSeriesCount);
        }
      }

      const formatterPaths = ["xAxis.axisLabel", "yAxis.axisLabel"];
      formatterPaths.forEach((path) => {
        const parts = path.split(".");

        const parent = parts.reduce((obj, part) => obj && obj[part], option);

        if (parent && parent.formatter && typeof parent.formatter === "string" && parent.formatter.startsWith("fn:")) {
          const functionName = parent.formatter.substring(3);
          if (functionName in formatters) {
            parent.formatter = formatters[functionName](this.el);
          } else if (window.nooraChartFormatters && functionName in window.nooraChartFormatters) {
            parent.formatter = window.nooraChartFormatters[functionName](this.el);
          }
        }
      });
    } catch (err) {
      console.error("Failed to parse ECharts options:", err);
    }

    return option;
  },
};
