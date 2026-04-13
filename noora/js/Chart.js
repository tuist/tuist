import * as echarts from "echarts";
import { parse, formatHex } from "culori";
import { formatHours } from "./formatters.js";

/**
 * Formats elapsed time into a human readable string
 * @param {number} milliseconds - The elapsed time in milliseconds
 * @returns {string} Formatted time string
 */
function formatSeconds(seconds) {
  if (seconds < 1) {
    return `${Math.round(seconds * 1000)}ms`;
  } else if (seconds < 60) {
    return `${Math.round(seconds * 10) / 10}s`;
  } else if (seconds == 60) {
    return "1m";
  } else if (seconds < 3600) {
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = Math.floor(seconds % 60);
    if (remainingSeconds == 0) {
      return `${minutes}m`;
    } else {
      return `${minutes}m ${remainingSeconds}s`;
    }
  } else if (seconds < 86400) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    if (minutes == 0) {
      return `${hours}h`;
    } else {
      return `${hours}h ${minutes}m`;
    }
  } else {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    return `${days}d ${hours}h`;
  }
}

function formatMilliseconds(milliseconds) {
  return formatSeconds(milliseconds / 1000);
}

function formatBytes(bytes) {
  if (bytes >= 1_000_000_000) {
    return `${(bytes / 1_000_000_000).toFixed(0)} GB`;
  } else if (bytes >= 1_000_000) {
    return `${(bytes / 1_000_000).toFixed(0)} MB`;
  } else if (bytes >= 1_000) {
    return `${(bytes / 1_000).toFixed(0)} KB`;
  } else {
    return `${bytes} MB`;
  }
}

const formatters = {
  toLocaleDate: (el) => (value, _) => {
    const date = new Date(value);
    return date.toLocaleDateString(navigator.language, {
      day: "numeric",
      month: "short",
    });
  },
  toLocaleTime: (el) => (value, _) => {
    const date = new Date(value);
    return date.toLocaleTimeString(navigator.language, {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    });
  },
  formatBytes: (el) => (value, _) => {
    return formatBytes(value);
  },
  formatMilliseconds: (el) => (value, _) => {
    return formatMilliseconds(value);
  },
  formatSeconds: (el) => (value, _) => {
    return formatSeconds(value);
  },
  formatHours: (el) => (value, _) => {
    return formatHours(value);
  },
};

const tooltipFormatters = {
  formatBytes,
  formatMilliseconds,
  formatSeconds,
  formatHours: (value) => formatHours(value, { includeMinutes: true }),
};

export default {
  mounted() {
    this.render();
    this.colorSchemeListener = () => this.render();
    window.addEventListener(
      "changed-preferred-theme",
      this.colorSchemeListener,
    );
  },
  render() {
    if (this.chart) this.chart.dispose();

    const option = this.option();
    const theme = getTheme(option);

    echarts.registerTheme("noora", theme);
    this.chart = echarts.init(
      this.el.querySelector("[data-part='chart']"),
      "noora",
      { renderer: "canvas" },
    );
    this.chart.setOption(option);

    const hasClickableData =
      option.series &&
      option.series.some(
        (s) =>
          s.data && s.data.some((d) => d && typeof d === "object" && d.url),
      );

    if (hasClickableData) {
      this.chart.on("click", (params) => {
        const dataItem = params.data;
        if (dataItem && dataItem.url) {
          window.location.href = dataItem.url;
        }
      });

      const chartDom = this.el.querySelector("[data-part='chart']");
      this.chart.on("mouseover", (params) => {
        if (params.data && params.data.url) {
          chartDom.style.cursor = "pointer";
        }
      });
      this.chart.on("mouseout", () => {
        chartDom.style.cursor = "default";
      });
    }

    this.resizeListener = () => {
      this.chart.resize();
    };
    window.addEventListener("resize", this.resizeListener);
    window.addEventListener("phx:resize", this.resizeListener);
  },
  updated() {
    // Re-render fully to update theme (including tooltip formatter)
    this.render();
  },
  destroyed() {
    this.chart.dispose();
    window.removeEventListener(
      "changed-preferred-theme",
      this.colorSchemeListener,
    );
    window.removeEventListener("resize", this.resizeListener);
    window.removeEventListener("phx:resize", this.resizeListener);
  },
  option() {
    let option = {};
    try {
      option = JSON.parse(
        this.el.querySelector("[data-part='data']").textContent,
      );

      if (
        option.legend &&
        option.legend.textStyle &&
        option.legend.textStyle.color
      ) {
        option.legend.textStyle.color = processColor(
          option.legend.textStyle.color,
        );
      }

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

        if (
          parent &&
          parent.formatter &&
          typeof parent.formatter === "string" &&
          parent.formatter.startsWith("fn:")
        ) {
          const functionName = parent.formatter.substring(3);
          if (functionName in formatters) {
            parent.formatter = formatters[functionName](this.el);
          } else if (
            window.nooraChartFormatters &&
            functionName in window.nooraChartFormatters
          ) {
            parent.formatter = window.nooraChartFormatters[functionName](
              this.el,
            );
          }
        }
      });
    } catch (err) {
      console.error("Failed to parse ECharts options:", err);
    }
    if (option.yAxis.splitLine.lineStyle.color) {
      option.yAxis.splitLine.lineStyle.color = processColor(
        option.yAxis.splitLine.lineStyle.color,
      );
    }
    if (option.yAxis.axisLabel.color) {
      option.yAxis.axisLabel.color = processColor(option.yAxis.axisLabel.color);
    }
    if (option.xAxis.axisLabel.color) {
      option.xAxis.axisLabel.color = processColor(option.xAxis.axisLabel.color);
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
      formatter: tooltipFormatter({
        valueFormat: option?.tooltip?.valueFormat,
        dateFormat: option?.tooltip?.dateFormat,
      }),
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
    const value = getComputedStyle(document.documentElement)
      .getPropertyValue(`--${variable}`)
      .trim();
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
  const currentTheme = localStorage.getItem("preferred-theme");
  if (currentTheme == "light") {
    return match[1];
  } else if (currentTheme == "dark") {
    return match[2];
  } else {
    return window.matchMedia("(prefers-color-scheme: light)").matches
      ? match[1]
      : match[2];
  }
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
    if (seriesItem.itemStyle && seriesItem.itemStyle.borderColor) {
      seriesItem.itemStyle.borderColor = processColor(
        seriesItem.itemStyle.borderColor,
      );
    }

    // Process colors in data items
    if (seriesItem.data && Array.isArray(seriesItem.data)) {
      seriesItem.data.forEach((dataItem) => {
        processItemColor(dataItem);
      });
    }

    return seriesItem;
  });
}

function processItemColor(dataItem) {
  if (dataItem && typeof dataItem === "object" && dataItem.itemStyle) {
    if (dataItem.itemStyle.color) {
      dataItem.itemStyle.color = processColor(dataItem.itemStyle.color);
    }
    if (dataItem.itemStyle.borderColor) {
      dataItem.itemStyle.borderColor = processColor(
        dataItem.itemStyle.borderColor,
      );
    }

    if (dataItem.children) {
      dataItem.children.forEach((child) => {
        processItemColor(child);
      });
    }
  }
}

function transformColorProperty(colorProp) {
  if (!colorProp) return colorProp;

  if (Array.isArray(colorProp)) {
    return colorProp.map((color) => processColor(color));
  }

  return processColor(colorProp);
}

// Tooltip
function tooltipFormatter(options = {}) {
  return (params) => {
    const paramsArray = Array.isArray(params) ? params : [params];
    const content = paramsArray
      .map((param) => tooltipSeries(param, options))
      .join("");
    let title = paramsArray[0].name;
    if (
      !title &&
      Array.isArray(paramsArray[0].value) &&
      paramsArray[0].value.length >= 2
    ) {
      const date = new Date(paramsArray[0].value[0]);
      if (!isNaN(date.getTime())) {
        title = date.toLocaleDateString(navigator.language, {
          day: "numeric",
          month: "short",
          year: "numeric",
          hour: "numeric",
          minute: "numeric",
        });
      }
    }
    if (!Number.isNaN(Date.parse(title))) {
      const date = new Date(title);
      if (options.dateFormat == "minute") {
        title = date.toLocaleDateString(navigator.language, {
          day: "numeric",
          month: "short",
          year: "numeric",
          hour: "numeric",
          minute: "numeric",
        });
      } else if (options.dateFormat == "hour") {
        const dateStr = date.toLocaleDateString(navigator.language, {
          day: "numeric",
          month: "short",
          year: "numeric",
        });
        const hour = String(date.getHours()).padStart(2, "0");
        title = `${dateStr}, ${hour}:00`;
      } else {
        title = date.toLocaleDateString(navigator.language, {
          day: "numeric",
          month: "short",
          year: "numeric",
        });
      }
    }
    // For scatter data points with tooltipExtra, add color dot and duration to header
    const firstData = paramsArray[0].data;
    let titleExtra = "";
    if (firstData && typeof firstData === "object" && firstData.tooltipExtra) {
      const color = Array.isArray(paramsArray[0].color)
        ? paramsArray[0].color[0]
        : paramsArray[0].color;
      titleExtra = `<span data-part="dot" style="--color: ${color}"></span>`;

      let rawValue = paramsArray[0].value;
      if (Array.isArray(rawValue) && rawValue.length > 1) {
        rawValue = rawValue[rawValue.length - 1];
      }
      let formatted;
      if (options.valueFormat && typeof options.valueFormat === "string") {
        if (options.valueFormat.startsWith("fn:")) {
          const fn = options.valueFormat.substring(3);
          if (fn in tooltipFormatters) formatted = tooltipFormatters[fn](rawValue);
        } else {
          formatted = options.valueFormat.replace("{value}", rawValue);
        }
      }
      if (formatted) title = `${title} · ${formatted}`;
    }

    return `<div class="noora-chart-tooltip">
      <span data-part="title">${titleExtra}${title}</span>
      <div class="noora-line-divider">
        <div data-part="line"></div>
      </div>
      ${content}
    </div>`;
  };
}

function tooltipSeries(param, options = {}) {
  let { color, seriesName, value, data } = param;
  if (!seriesName && Array.isArray(value)) {
    const date = new Date(value[0]);
    if (date instanceof Date && !isNaN(date)) {
      seriesName = new Intl.DateTimeFormat(navigator.language).format(date);
      value = value[1];
    }
  }
  if (Array.isArray(value) && value.length > 0) {
    value = value[value.length - 1];
  }
  if (value !== null && typeof value === "object" && "value" in value) {
    value = value.value;
  }

  let formattedValue;
  if (options.valueFormat && typeof options.valueFormat === "string") {
    if (options.valueFormat.startsWith("fn:")) {
      const functionName = options.valueFormat.substring(3);
      if (functionName in tooltipFormatters) {
        formattedValue = tooltipFormatters[functionName](value);
      }
    } else {
      formattedValue = options.valueFormat.replace("{value}", value);
    }
  } else {
    formattedValue = value;
  }

  const hasExtra = data && typeof data === "object" && data.tooltipExtra;

  if (hasExtra) {
    const extraLines = data.tooltipExtra
      .map(
        ({ label, value: v }) =>
          `<div data-part="series-item"><span data-part="label">${label}</span><span data-part="value">${v}</span></div>`,
      )
      .join("");

    return extraLines;
  }

  return `
  <div data-part="series-item">
    <span data-part="dot" style="--color: ${Array.isArray(color) ? color[0] : color}"></span>
    <span data-part="label">${seriesName}</span>
    <span data-part="value">${formattedValue}</span>
  </div>
  `;
}
