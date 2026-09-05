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

function formatCurrency(amount, currency = "USD") {
  return Number(amount).toLocaleString(navigator.language, {
    style: "currency",
    currency,
  });
}

function formatMbps(bytesPerSecond) {
  const mbps = (bytesPerSecond * 8) / 1_000_000;
  return `${mbps.toFixed(1)} Mbps`;
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
  toLocaleDateHour: (el) => (value, _) => {
    const date = new Date(value);
    const dateStr = date.toLocaleDateString(navigator.language, {
      day: "numeric",
      month: "short",
    });
    const hour = String(date.getHours()).padStart(2, "0");
    return `${dateStr}, ${hour}:00`;
  },
  formatBytes: (el) => (value, _) => {
    return formatBytes(value);
  },
  formatCurrency: (el) => (value, _) => {
    return formatCurrency(value);
  },
  formatMbps: (el) => (value, _) => {
    return formatMbps(value);
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
  formatCurrency,
  formatMbps,
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
  render({ animate = true } = {}) {
    if (this.chart) this.chart.dispose();

    const option = this.option();
    if (!animate) option.animation = false;
    const theme = getNooraChartTheme(option);

    echarts.registerTheme("noora", theme);
    const chartDom = this.el.querySelector("[data-part='chart']");
    this.chart = echarts.init(chartDom, "noora", { renderer: "canvas" });
    this.chart.setOption(option);
    // Expose the instance on the chart element so code outside this hook
    // (and outside Noora's bundled ECharts) can drive the chart — e.g. an
    // external hover adding a markArea — without echarts.getInstanceByDom,
    // which only resolves instances created by the same ECharts copy.
    chartDom.__nooraChart = this.chart;

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
    // Re-render fully to update theme (including tooltip formatter), but skip
    // the entry animation so LiveView patches don't visibly re-animate charts.
    this.render({ animate: false });
  },
  destroyed() {
    const chartDom = this.el.querySelector("[data-part='chart']");
    if (chartDom) chartDom.__nooraChart = null;
    this.chart.dispose();
    window.removeEventListener(
      "changed-preferred-theme",
      this.colorSchemeListener,
    );
    window.removeEventListener("resize", this.resizeListener);
    window.removeEventListener("phx:resize", this.resizeListener);
  },
  option() {
    try {
      return prepareChartOptions(
        JSON.parse(this.el.querySelector("[data-part='data']").textContent),
        this.el,
      );
    } catch (err) {
      console.error("Failed to parse ECharts options:", err);
      return {};
    }
  },
};

// Private helper functions

// Theme
export function getNooraChartTheme(option) {
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

export function prepareChartOptions(input, element) {
  const option = cloneChartValue(input);

  if (option.legend?.textStyle?.color) {
    option.legend.textStyle.color = processColor(option.legend.textStyle.color);
  }

  if (Array.isArray(option.series)) {
    option.series = processSeriesColors(option.series);

    const largestSeriesCount = option.series.reduce(
      (largestCount, series) =>
        Array.isArray(series.data)
          ? Math.max(largestCount, series.data.length)
          : largestCount,
      0,
    );

    if (largestSeriesCount > 0) {
      element?.setAttribute("data-largest-series-count", largestSeriesCount);
    }
  }

  for (const path of ["xAxis.axisLabel", "yAxis.axisLabel"]) {
    const parent = path
      .split(".")
      .reduce((object, part) => object?.[part], option);

    if (
      typeof parent?.formatter === "string" &&
      parent.formatter.startsWith("fn:")
    ) {
      const functionName = parent.formatter.substring(3);
      if (functionName in formatters) {
        parent.formatter = formatters[functionName](element);
      } else if (
        window.nooraChartFormatters &&
        functionName in window.nooraChartFormatters
      ) {
        parent.formatter = window.nooraChartFormatters[functionName](element);
      }
    }
  }

  if (option.tooltip?.formatter === "fn:rangeBarTooltip") {
    option.tooltip.formatter = rangeBarTooltipFormatter;
    option.tooltip.trigger ??= "item";
  }

  if (Array.isArray(option.series)) {
    let hasRangeBarSeries = false;

    option.series.forEach((series) => {
      if (series.renderItem === "fn:rangeBar") {
        series.renderItem = rangeBarRenderItem;
        series.encode ??= { x: [1, 2], y: 0 };
        hasRangeBarSeries = true;
      }
    });

    if (hasRangeBarSeries) {
      const hasMultipleXAxes = Array.isArray(option.xAxis);
      const hasMultipleYAxes = Array.isArray(option.yAxis);
      const xAxes = hasMultipleXAxes ? option.xAxis : [option.xAxis];
      const yAxes = hasMultipleYAxes ? option.yAxis : [option.yAxis];
      const xAxis = { ...(xAxes[0] ?? {}) };
      const yAxis = { ...(yAxes[0] ?? {}) };

      if (yAxis.data === undefined && Array.isArray(xAxis.data)) {
        yAxis.data = xAxis.data;
        delete xAxis.data;
      }

      const rangeXAxis = { ...xAxis, type: "value" };
      const rangeYAxis = { ...yAxis, type: "category" };
      option.xAxis = hasMultipleXAxes
        ? [rangeXAxis, ...xAxes.slice(1)]
        : rangeXAxis;
      option.yAxis = hasMultipleYAxes
        ? [rangeYAxis, ...yAxes.slice(1)]
        : rangeYAxis;
    }
  }

  if (option.yAxis?.splitLine?.lineStyle?.color) {
    option.yAxis.splitLine.lineStyle.color = processColor(
      option.yAxis.splitLine.lineStyle.color,
    );
  }
  if (option.yAxis?.axisLabel?.color) {
    option.yAxis.axisLabel.color = processColor(option.yAxis.axisLabel.color);
  }
  if (option.xAxis?.axisLabel?.color) {
    option.xAxis.axisLabel.color = processColor(option.xAxis.axisLabel.color);
  }

  return option;
}

function cloneChartValue(value) {
  if (Array.isArray(value)) return value.map(cloneChartValue);
  if (
    value &&
    typeof value === "object" &&
    Object.getPrototypeOf(value) === Object.prototype
  ) {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, cloneChartValue(item)]),
    );
  }
  return value;
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
  const chartColors = Array.isArray(option.colors)
    ? option.colors
    : [
        "var:noora-chart-primary",
        "var:noora-chart-secondary",
        "var:noora-chart-tertiary",
        "var:noora-chart-quaternary",
      ];
  return chartColors.map(processColor);
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

function rangeBarRenderItem(params, api) {
  const lane = api.value(0);
  const start = api.value(1);
  const end = api.value(2);

  if (
    !Number.isFinite(lane) ||
    !Number.isFinite(start) ||
    !Number.isFinite(end) ||
    end < start
  ) {
    return null;
  }

  const startCoordinate = api.coord([start, lane]);
  const endCoordinate = api.coord([end, lane]);
  const height = api.size([0, 1])[1] * 0.62;
  const shape = echarts.graphic.clipRectByRect(
    {
      x: startCoordinate[0],
      y: startCoordinate[1] - height / 2,
      width: Math.max(endCoordinate[0] - startCoordinate[0], 1),
      height,
    },
    {
      x: params.coordSys.x,
      y: params.coordSys.y,
      width: params.coordSys.width,
      height: params.coordSys.height,
    },
  );

  if (!shape) return null;

  return {
    type: "rect",
    shape,
    style: api.style(),
  };
}

export function rangeBarTooltipFormatter(params) {
  const param = Array.isArray(params) ? params[0] : params;
  if (!param) return "";

  const [, start, end] = Array.isArray(param.value) ? param.value : [];
  const duration =
    Number.isFinite(start) && Number.isFinite(end) && end >= start
      ? end - start
      : null;
  const data = param.data && typeof param.data === "object" ? param.data : {};
  const description = data.name || param.name;
  const rows = [
    rangeBarTooltipRow(data.durationLabel, duration),
    rangeBarTooltipRow(data.startLabel, start),
  ].filter(Boolean);
  const title = description
    ? `<span data-part="title">${escapeHtml(description)}</span>`
    : "";
  const divider =
    description && rows.length > 0
      ? '<div class="noora-line-divider"><div data-part="line"></div></div>'
      : "";

  if (!title && rows.length === 0) return "";

  return `<div class="noora-chart-tooltip">${title}${divider}${rows.join("")}</div>`;
}

function rangeBarTooltipRow(label, value) {
  if (!label) return "";

  const formattedValue = Number.isFinite(value)
    ? formatMilliseconds(value)
    : "\u2014";
  const labelElement = `<span data-part="label">${escapeHtml(label)}</span>`;

  return `<div data-part="series-item">${labelElement}<span data-part="value">${escapeHtml(formattedValue)}</span></div>`;
}

function transformColorProperty(colorProp) {
  if (!colorProp) return colorProp;

  if (Array.isArray(colorProp)) {
    return colorProp.map((color) => processColor(color));
  }

  return processColor(colorProp);
}

// Tooltip strings are returned to ECharts and rendered via innerHTML
// (renderMode defaults to "html"), so any interpolated value derived from
// user-uploaded data (scheme, project name, category, etc.) must be escaped.
function escapeHtml(value) {
  if (value === null || value === undefined) return "";
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
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
      titleExtra = `<span data-part="dot" style="--color: ${escapeHtml(color)}"></span>`;

      let rawValue = paramsArray[0].value;
      if (Array.isArray(rawValue) && rawValue.length > 1) {
        rawValue = rawValue[rawValue.length - 1];
      }
      let formatted;
      if (options.valueFormat && typeof options.valueFormat === "string") {
        if (options.valueFormat.startsWith("fn:")) {
          const fn = options.valueFormat.substring(3);
          if (fn in tooltipFormatters)
            formatted = tooltipFormatters[fn](rawValue);
        } else {
          formatted = options.valueFormat.replace("{value}", rawValue);
        }
      }
      if (formatted) title = `${title} · ${formatted}`;
    }

    return `<div class="noora-chart-tooltip">
      <span data-part="title">${titleExtra}${escapeHtml(title)}</span>
      <div class="noora-line-divider">
        <div data-part="line"></div>
      </div>
      ${content}
    </div>`;
  };
}

export function tooltipSeries(param, options = {}) {
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

  // A null value is a bucket with nothing in it, not a measurement of zero.
  // Running it through a formatter would print "0ms" and read as a real
  // observation, so the series says it has no value for this point instead.
  if (value === null || value === undefined) {
    return seriesItem(color, seriesName, "\u2014");
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
          `<div data-part="series-item"><span data-part="label">${escapeHtml(label)}</span><span data-part="value">${escapeHtml(v)}</span></div>`,
      )
      .join("");

    return extraLines;
  }

  return seriesItem(color, seriesName, formattedValue);
}

function seriesItem(color, seriesName, formattedValue) {
  const dotColor = Array.isArray(color) ? color[0] : color;
  return `
  <div data-part="series-item">
    <span data-part="dot" style="--color: ${escapeHtml(dotColor)}"></span>
    <span data-part="label">${escapeHtml(seriesName)}</span>
    <span data-part="value">${escapeHtml(formattedValue)}</span>
  </div>
  `;
}
