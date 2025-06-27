function findNode(data, predicate) {
  for (const node of data) {
    if (predicate(node)) {
      return node;
    }
    if (node.children) {
      const found = findNode(node.children, predicate);
      if (found) return found;
    }
  }
  return null;
}

export default {
  mounted() {
    const chart = document.querySelector(`#${this.el.dataset.chartId}`);

    if (chart) {
      const chartPart = chart.querySelector('[data-part="chart"]');
      const element = chartPart || chart;
      const chartContainer = element.closest(".noora-chart");

      if (chartContainer && window.liveSocket && window.liveSocket.roots) {
        for (const rootId in window.liveSocket.roots) {
          const view = window.liveSocket.roots[rootId];
          if (view && view.el && view.el.contains(chartContainer)) {
            if (view.getHook) {
              const hook = view.getHook(chartContainer);
              if (hook && hook.chart) {
                this.setupChartHandlers(hook.chart);
                return;
              }
            }
          }
        }
      }
    }
  },

  setupChartHandlers(echart) {
    this.handleBreadcrumbClicked = (event) => {
      if (event.target.id == this.el.id && echart) {
        const node = findNode(echart.getOption().series[0].data, (node) => node.id == event.detail.artifact_id);
        if (node) {
          echart.dispatchAction({
            type: "sunburstRootToNode",
            seriesIndex: 0,
            targetNodeId: event.detail.artifact_id,
          });
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-artifact", {
            artifact: {
              value: node.value,
              name: node.name,
              artifact_type: node.artifact_type,
              artifact_id: node.artifact_id,
              children: node.children || [],
              path: node.path,
            },
          });
        } else {
          echart.dispatchAction({ type: "sunburstRootToNode", seriesIndex: 0, targetNode: "" });
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-root", {});
        }
      }
    };
    window.addEventListener("bundle-size-analysis-breadcrumb-clicked", this.handleBreadcrumbClicked);

    this.handleTableRowClicked = (event) => {
      if (event.target.id == this.el.id && echart) {
        const artifact = event.detail.artifact;

        if (artifact.artifact_type === "directory" || artifact.artifact_type === "asset") {
          let node;
          const seriesData = echart.getOption().series[0].data;

          if (artifact.path) {
            node = findNode(seriesData, (node) => node.path === artifact.path);
          }

          if (!node && artifact.artifact_id) {
            node = findNode(seriesData, (node) => node.artifact_id === artifact.artifact_id);
          }

          if (node) {
            echart.dispatchAction({
              type: "sunburstRootToNode",
              seriesIndex: 0,
              targetNodeId: node.id,
            });
            this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-artifact", {
              artifact: {
                value: node.value,
                name: node.name,
                artifact_type: node.artifact_type,
                artifact_id: node.artifact_id,
                children: node.children || [],
                path: node.path,
              },
            });
          }
        } else {
          const seriesData = echart.getOption().series[0].data;
          const fileNode = findNode(seriesData, (node) => {
            return node.path === artifact.path;
          });

          if (fileNode) {
            echart.dispatchAction({
              type: "highlight",
              seriesIndex: 0,
              name: artifact.name,
            });
          }
        }
      }
    };
    window.addEventListener("bundle-size-analysis-table-row-clicked", this.handleTableRowClicked);

    let highlightedNewElement = false;
    this.handleOnHighlighted = (el) => {
      highlightedNewElement = true;
      if (el.name == "") {
        this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-highlighted-parent", {});
      } else if (el.data) {
        this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-highlighted-artifact", {
          artifact: {
            value: el.data.value,
            artifact_type: el.data.artifact_type,
            name: el.data.name,
            artifact_id: el.data.artifact_id,
            children: el.data.children || [],
            path: el.data.path,
          },
        });
      }
    };

    echart.on("mouseover", this.handleOnHighlighted);
    echart.on("mouseout", (el) => {
      highlightedNewElement = false;
      setTimeout(() => {
        if (highlightedNewElement === false) {
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-no-highlighted-artifact", {});
        }
      }, 10);
    });
    echart.on("click", (params) => {
      if (params.name == "") {
        this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-parent", {});
      } else if (params.data) {
        this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-artifact", {
          artifact: {
            value: params.data.value,
            name: params.data.name,
            artifact_type: params.data.artifact_type,
            artifact_id: params.data.artifact_id,
            children: params.data.children || [],
            path: params.data.path,
          },
        });
      }
    });
  },

  destroyed() {
    if (this.handleBreadcrumbClicked) {
      window.removeEventListener("bundle-size-analysis-breadcrumb-clicked", this.handleBreadcrumbClicked);
    }
    if (this.handleTableRowClicked) {
      window.removeEventListener("bundle-size-analysis-table-row-clicked", this.handleTableRowClicked);
    }
  },
};
