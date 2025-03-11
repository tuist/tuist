import * as echarts from "echarts";
import { parse, formatHex } from "culori";

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

export default {
  mounted() {
    this.render();
    this.colorSchemeListener = () => this.render();
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", this.colorSchemeListener);
  },
  render() {
    if (this.chart) this.chart.dispose();

    const option = this.option();
    const theme = getTheme(option);

    echarts.registerTheme("noora", theme);
    this.chart = echarts.init(this.el.querySelector("[data-part='chart']"), "noora", { renderer: "canvas" });
    this.chart.setOption(option);

    this.resizeListener = () => {
      this.chart.resize();
    };
    window.addEventListener("resize", this.resizeListener);
  },
  updated() {
    const option = this.option();
    this.chart.setOption(option);
  },
  destroyed() {
    this.chart.dispose();
    window.matchMedia("(prefers-color-scheme: dark)").removeEventListener("change", this.colorSchemeListener);
    window.removeEventListener("resize", this.resizeListener);
  },
  option() {
    let option = {};
    try {
      option = JSON.parse(this.el.querySelector("[data-part='data']").textContent);

      if (option.series && Array.isArray(option.series)) {
        option.series = processSeriesColors(option.series);

        // Calculate the size of the largest series which we use for later calculations.
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

// Private helper functions

// Theme
function getTheme(option) {
  return {
    color: colors(option),
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
    line: {
      emphasis: {
        lineStyle: {
          width: "bolder",
        },
      },
    },
  };
}

function processColor(color) {
  if (typeof color === "string" && color.startsWith("var:")) {
    const variable = color.substring(4);
    const value = getComputedStyle(document.documentElement).getPropertyValue(`--${variable}`).trim();
    color = resolveLightDark(value);
  }

  // ECharts expects colors to be hex and shows unintended behavior such as broken hover states when using OKLCH, which we are generally
  // using elsewhere.
  return formatHex(parse(color));
}

function resolveLightDark(string) {
  const regex = /light-dark\(\s*(.*?)\s*,\s*(.*?)\s*\)$/;
  const match = string.match(regex);
  if (!match) return string;
  return window.matchMedia("(prefers-color-scheme: light)").matches ? match[1] : match[2];
}

function colors(option) {
  if (!option.colors || !Array.isArray(option.colors)) return [];
  return option.colors.map(processColor);
}

function processSeriesColors(series) {
  if (!series || !Array.isArray(series)) return series;

  return series.map((seriesItem) => {
    // Process top-level color property
    seriesItem.color = transformColorProperty(seriesItem.color);

    // Process style objects with color properties
    const styleProperties = ["itemStyle", "lineStyle", "areaStyle"];
    styleProperties.forEach((styleProp) => {
      if (seriesItem[styleProp] && seriesItem[styleProp].color) {
        seriesItem[styleProp].color = processColor(seriesItem[styleProp].color);
      }
    });

    // Process colors in data items
    if (seriesItem.data && Array.isArray(seriesItem.data)) {
      seriesItem.data.forEach((dataItem) => {
        if (dataItem && typeof dataItem === "object" && dataItem.itemStyle && dataItem.itemStyle.color) {
          dataItem.itemStyle.color = processColor(dataItem.itemStyle.color);
        }
      });
    }

    return seriesItem;
  });
}

function transformColorProperty(colorProp) {
  if (!colorProp) return colorProp;

  if (Array.isArray(colorProp)) {
    return colorProp.map((color) => processColor(color));
  }

  return processColor(colorProp);
}

// Tooltip
function tooltipFormatter(params) {
  const content = Array.isArray(params) ? params.map(tooltipSeries).join("") : tooltipSeries(params);
  return `<div class="noora-chart-tooltip">${content}</div>`;
}

function tooltipSeries({ color, name, value }) {
  const displayValue = formatTooltipValue(value);

  return `
  <div data-part="series-item">
    <span data-part="dot" style="--color: ${Array.isArray(color) ? color[0] : color}"></span>
    <span data-part="label">${name}</span>
    <span data-part="value">${displayValue}</span>
  </div>
  `;
}

function formatTooltipValue(value) {
  if (Array.isArray(value) && value.length > 0) {
    return value[value.length - 1];
  }

  if (value !== null && typeof value === "object" && "value" in value) {
    return value.value;
  }

  return value;
}
