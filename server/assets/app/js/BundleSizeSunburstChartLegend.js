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

// A directory with a single child is merged into the child's node, which keeps the child's
// path, so a directory without a node of its own resolves to the merged node below it.
function findNodeByPath(data, path) {
  return (
    findNode(data, (node) => node.path === path) ||
    findNode(data, (node) => node.path && node.path.startsWith(`${path}/`))
  );
}

function selectedArtifact(node) {
  return {
    value: node.value,
    name: node.name,
    artifact_type: node.artifact_type,
    artifact_id: node.artifact_id,
    children: node.children || [],
    path: node.path,
  };
}

export default {
  mounted() {
    this.chartDom = document.getElementById(`${this.el.dataset.chartId}-chart`);
    this.highlightedNewElement = false;

    this.chartHandlers = {
      mouseover: (el) => {
        this.highlightedNewElement = true;
        if (el.name == "") {
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-highlighted-parent", {});
        } else if (el.data) {
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-highlighted-artifact", {
            artifact: selectedArtifact(el.data),
          });
        }
      },
      mouseout: () => {
        this.highlightedNewElement = false;
        setTimeout(() => {
          if (this.highlightedNewElement === false) {
            this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-no-highlighted-artifact", {});
          }
        }, 10);
      },
      click: (params) => {
        if (params.name == "") {
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-parent", {});
        } else if (params.data) {
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-artifact", {
            artifact: selectedArtifact(params.data),
          });
        }
      },
    };

    this.handleBreadcrumbClicked = (event) => {
      if (event.target.id != this.el.id || !this.echart) return;

      const path = event.detail.path;
      const node = path && findNodeByPath(this.echart.getOption().series[0].data, path);
      if (node) {
        this.echart.dispatchAction({ type: "sunburstRootToNode", seriesIndex: 0, targetNodeId: node.id });
        this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-artifact", {
          artifact: selectedArtifact(node),
        });
      } else {
        this.echart.dispatchAction({ type: "sunburstRootToNode", seriesIndex: 0, targetNode: "" });
        this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-root", {});
      }
    };
    window.addEventListener("bundle-size-analysis-breadcrumb-clicked", this.handleBreadcrumbClicked);

    this.handleTableRowClicked = (event) => {
      if (event.target.id != this.el.id || !this.echart) return;

      const artifact = event.detail.artifact;
      const seriesData = this.echart.getOption().series[0].data;

      if (artifact.artifact_type === "directory" || artifact.artifact_type === "asset") {
        const node = artifact.path && findNodeByPath(seriesData, artifact.path);

        if (node) {
          this.echart.dispatchAction({ type: "sunburstRootToNode", seriesIndex: 0, targetNodeId: node.id });
          this.pushEvent("update-bundle-size-analysis-sunburst-chart-table-selected-artifact", {
            artifact: selectedArtifact(node),
          });
        }
      } else if (findNode(seriesData, (node) => node.path === artifact.path)) {
        this.echart.dispatchAction({ type: "highlight", seriesIndex: 0, name: artifact.name });
      }
    };
    window.addEventListener("bundle-size-analysis-table-row-clicked", this.handleTableRowClicked);

    // Noora disposes and re-creates the ECharts instance whenever the chart re-renders, which
    // replaces the instance's DOM inside the chart element.
    this.chartObserver = new MutationObserver(() => this.bindChart());
    if (this.chartDom) this.chartObserver.observe(this.chartDom, { childList: true });
    this.bindChart();
  },

  bindChart() {
    const echart = this.chartDom && this.chartDom.__nooraChart;
    if (!echart || echart === this.echart) return;

    this.unbindChart();
    this.echart = echart;
    for (const [eventName, handler] of Object.entries(this.chartHandlers)) {
      echart.on(eventName, handler);
    }
    this.drillToCurrentPath();
  },

  unbindChart() {
    if (this.echart && !this.echart.isDisposed()) {
      for (const [eventName, handler] of Object.entries(this.chartHandlers)) {
        this.echart.off(eventName, handler);
      }
    }
    this.echart = null;
  },

  drillToCurrentPath() {
    const path = this.el.dataset.currentPath;
    if (!path) return;

    const node = findNodeByPath(this.echart.getOption().series[0].data, path);
    if (node) {
      this.echart.dispatchAction({ type: "sunburstRootToNode", seriesIndex: 0, targetNodeId: node.id });
    }
  },

  destroyed() {
    this.chartObserver.disconnect();
    this.unbindChart();
    window.removeEventListener("bundle-size-analysis-breadcrumb-clicked", this.handleBreadcrumbClicked);
    window.removeEventListener("bundle-size-analysis-table-row-clicked", this.handleTableRowClicked);
  },
};
