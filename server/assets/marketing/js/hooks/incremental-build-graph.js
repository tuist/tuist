import cytoscape from "cytoscape";
import dagre from "cytoscape-dagre";

cytoscape.use(dagre);

const elements = [
  { data: { id: "shared", label: "shared API" } },
  { data: { id: "feature", label: "feature" } },
  { data: { id: "service", label: "service" } },
  { data: { id: "tooling", label: "tooling" } },
  { data: { id: "app", label: "app" } },
  { data: { id: "cli", label: "command line" } },
  { data: { id: "shared-service", source: "shared", target: "service" } },
  { data: { id: "shared-tooling", source: "shared", target: "tooling" } },
  { data: { id: "feature-service", source: "feature", target: "service" } },
  { data: { id: "service-app", source: "service", target: "app" } },
  { data: { id: "tooling-cli", source: "tooling", target: "cli" } },
];

const buildStages = {
  leaf: [["feature"], ["service"], ["app"]],
  shared: [["shared"], ["service", "tooling"], ["app", "cli"]],
};

function colorToken(element, token) {
  const probe = document.createElement("span");
  probe.style.color = `var(${token})`;
  element.append(probe);

  const context = document.createElement("canvas").getContext("2d");
  context.fillStyle = getComputedStyle(probe).color;
  context.fillRect(0, 0, 1, 1);

  const [red, green, blue, alpha] = context.getImageData(0, 0, 1, 1).data;
  probe.remove();

  return `rgba(${red}, ${green}, ${blue}, ${alpha / 255})`;
}

function bodySmallTypography(element) {
  const probe = document.createElement("span");
  probe.style.font = "var(--noora-font-body-small)";
  probe.style.fontWeight = "var(--noora-font-weight-medium)";
  element.append(probe);

  const styles = getComputedStyle(probe);
  const typography = {
    family: styles.fontFamily,
    size: styles.fontSize,
    weight: styles.fontWeight,
  };

  probe.remove();

  return typography;
}

const IncrementalBuildGraph = {
  mounted() {
    this.timers = [];
    this.createGraph();
    this.run = this.el.dataset.run;
    this.updateGraph();
  },

  updated() {
    if (!this.el.querySelector("canvas")) {
      this.graph?.destroy();
      this.createGraph();
      this.run = this.el.dataset.run;
      this.updateGraph();
      return;
    }

    const run = this.el.dataset.run;

    if (run === this.run) return;

    this.run = run;
    this.updateGraph({ animated: true });
  },

  destroyed() {
    this.clearTimers();
    this.graph?.destroy();
  },

  createGraph() {
    const typography = bodySmallTypography(this.el);
    const colors = {
      background: colorToken(this.el, "--noora-surface-background-primary"),
      border: colorToken(this.el, "--noora-surface-border-primary"),
      changed: colorToken(this.el, "--noora-button-primary-background"),
      changedLabel: colorToken(this.el, "--noora-button-primary-label"),
      invalidated: colorToken(this.el, "--noora-purple-100"),
      label: colorToken(this.el, "--noora-surface-label-primary"),
    };

    this.graph = cytoscape({
      container: this.el,
      elements,
      userZoomingEnabled: false,
      userPanningEnabled: false,
      boxSelectionEnabled: false,
      style: [
        {
          selector: "node",
          style: {
            label: "data(label)",
            color: colors.label,
            "font-family": typography.family,
            "font-size": typography.size,
            "font-weight": typography.weight,
            "text-valign": "center",
            "text-halign": "center",
            width: 132,
            height: 48,
            shape: "round-rectangle",
            "background-color": colors.background,
            "border-color": colors.border,
            "border-width": 2,
            "transition-property": "background-color, border-color, color",
            "transition-duration": "180ms",
            "transition-timing-function": "ease-out",
          },
        },
        {
          selector: "edge",
          style: {
            width: 2,
            "line-color": colors.border,
            "target-arrow-color": colors.border,
            "target-arrow-shape": "triangle",
            "curve-style": "bezier",
            "transition-property": "line-color, target-arrow-color, width",
            "transition-duration": "180ms",
            "transition-timing-function": "ease-out",
          },
        },
        {
          selector: ".invalidated",
          style: {
            "background-color": colors.invalidated,
            "border-color": colors.changed,
            "border-width": 3,
          },
        },
        {
          selector: ".changed",
          style: {
            "background-color": colors.changed,
            "border-color": colors.changed,
            color: colors.changedLabel,
          },
        },
        {
          selector: ".affected",
          style: {
            width: 3,
            "line-color": colors.changed,
            "target-arrow-color": colors.changed,
            "line-style": "dashed",
          },
        },
      ],
      layout: {
        name: "dagre",
        rankDir: "LR",
        rankSep: 100,
        nodeSep: 42,
        edgeSep: 28,
        padding: 20,
      },
    });
  },

  clearTimers() {
    this.timers?.forEach((timer) => window.clearTimeout(timer));
    this.timers = [];
  },

  updateGraph({ animated = false } = {}) {
    this.clearTimers();

    const change = this.el.dataset.change;
    const stages = buildStages[change];
    const changedTask = change === "leaf" ? "feature" : "shared";
    const completed = new Set();

    this.graph.elements().removeClass("invalidated changed affected");

    const activate = (stage) => {
      stage.forEach((id) => {
        completed.add(id);
        const node = this.graph.$id(id);
        node.addClass(id === changedTask ? "changed" : "invalidated");
      });

      this.graph.edges().forEach((edge) => {
        if (completed.has(edge.source().id()) && completed.has(edge.target().id())) {
          edge.addClass("affected");
        }
      });
    };

    if (!animated) {
      stages.forEach(activate);
      return;
    }

    stages.forEach((stage, index) => {
      this.timers.push(window.setTimeout(() => activate(stage), index * 520));
    });
  },
};

export { IncrementalBuildGraph };
