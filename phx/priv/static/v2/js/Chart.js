/**
 * @module chart-l
 * @description
 * A reusable chart component.
 */
class ChartComponent extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
  }

  connectedCallback() {
    this.render();
  }

  render() {
    function cssvar(name) {
      return getComputedStyle(
        document.documentElement,
      ).getPropertyValue(name);
    }

    const chartDiv = document.createElement('div');
    this.shadowRoot.appendChild(chartDiv);

    const options = {
      series: [this.data],
      chart: {
        height: '400px',
        type: 'area',
        toolbar: {
          show: false,
        },
        zoom: {
          enabled: false,
        },
      },
      colors: [cssvar('--utility-brand-600')],
      dataLabels: {
        enabled: false,
      },
      fill: {
        colors: [cssvar('--utility-brand-600')],
        type: 'gradient',
        gradient: {
          shade: 'dark',
          type: 'vertical',
          opacityFrom: 0.6,
          opacityTo: 0,
          stops: [0, 100],
          colorStops: [],
        },
      },
      grid: {
        borderColor: cssvar('--border-tertiary'),
      },
      xaxis: {
        categories: this.data.labels,
        tickAmount:
          this.data.labels.length > 12
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
            colors: cssvar('--text-tertiary'),
            cssClass: 'text-xs text--regular color--text-tertiary',
          },
        },
      },
      yaxis: {
        labels: {
          formatter: this.yLabelFormatter,
        },
      },
    };

    var chart = new ApexCharts(chartDiv, options);
    chart.render();
  }

  get data() {
    return (
      this.getAttribute('data') ?? {
        data: [],
        labels: [],
        name: '',
      }
    );
  }

  set data(val) {
    return this.setAttribute(val);
  }

  get yLabelFormatter() {
    return this.getAttribute('yLabelFormatter') ?? ((val) => val);
  }

  set yLabelFormatter(val) {
    return this.setAttribute(val);
  }
}

customElements.define('chart-l', ChartComponent);
