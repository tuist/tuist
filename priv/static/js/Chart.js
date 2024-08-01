/**
 * @module chart-l
 * @description
 * A reusable chart component.
 */
class ChartComponent extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
  }

  render() {
    const chartDiv = document.createElement("div");
    this.shadowRoot.appendChild(chartDiv);

    let yLabelFormatter;
    switch (this.formatter) {
      case "none":
        yLabelFormatter = (value) => {
          return value;
        };
        break;
      case "seconds":
        yLabelFormatter = (value) => {
          return `${value} s`;
        };
        break;
      case "percentage":
        yLabelFormatter = (value) => {
          return `${(value * 100).toFixed(1)}%`;
        };
        break;
    }

    const options = {
      series: this.type == "donut" ? this.data.data : [this.data],
      labels: this.data.labels,
      stroke: this.stroke,

      responsive: [
        {
          breakpoint: undefined,
          options: {},
        },
      ],
      chart: {
        height: "400px",
        type: this.type,
        toolbar: {
          show: false,
        },
        zoom: {
          enabled: false,
        },
      },
      colors: this.colors,
      dataLabels: {
        enabled: false,
      },
      fill: {
        colors: this.colors,
        gradient: {
          shade: "dark",
          type: "vertical",
          opacityFrom: 0.6,
          opacityTo: 0,
          stops: [0, 100],
          colorStops: [],
        },
      },
      grid: {
        borderColor: cssvar("--border-tertiary"),
      },
      tooltip: {
        intersect: false,
      },
      legend: {
        position: "left",
        labels: {
          colors: cssvar("--text-tertiary"),
        },
      },
      xaxis: {
        categories: this.data.labels,
        tickAmount:
          this.data.labels && this.data.labels.length > 12
            ? this.data.labels.length / 2
            : this.data.labels.length,
        axisTicks: {
          show: false,
        },
        axisBorder: {
          show: false,
        },
        labels: {
          style: {
            colors: cssvar("--text-tertiary"),
            cssClass: "text-xs text--regular color--text-tertiary",
          },
        },
      },
      yaxis: {
        min: 0,
        max: this.maxYValue,
        labels: {
          formatter: yLabelFormatter,
        },
      },
      plotOptions: this.plotOptions,
    };

    var chart = new ApexCharts(chartDiv, options);
    chart.render();
  }

  get data() {
    return (
      JSON.parse(this.getAttribute("data")) ?? {
        data: [],
        labels: [],
        name: "",
      }
    );
  }

  set data(val) {
    return this.setAttribute("data", JSON.stringify(val));
  }

  get formatter() {
    return this.getAttribute("formatter");
  }

  set formatter(val) {
    return this.setAttribute("formatter", val);
  }

  get type() {
    return this.getAttribute("type") || "area";
  }

  set type(val) {
    return this.setAttribute("type", val);
  }

  get maxYValue() {
    return this.getAttribute("maxYValue") ?? undefined;
  }

  set maxYValue(val) {
    return this.setAttribute("maxYValue", val);
  }

  get colors() {
    return this.getAttribute("colors") ?? [cssvar("--utility-brand-500")];
  }

  set colors(val) {
    return this.setAttribute("colors", val);
  }

  get plotOptions() {
    return this.getAttribute("plotOptions") ?? {};
  }

  set plotOptions(val) {
    return this.setAttribute("plotOptions", val);
  }

  get stroke() {
    return this.getAttribute("stroke") ?? {};
  }

  set stroke(val) {
    return this.setAttribute("stroke", val);
  }
}

customElements.define("chart-l", ChartComponent);
