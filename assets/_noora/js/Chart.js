import * as echarts from "echarts";

export default {
  mounted() {
    this.chart = echarts.init(this.el, null, { renderer: "canvas" });
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
