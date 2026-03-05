function setupCodeGroups(el) {
  const groups = el.querySelectorAll(".code-group");

  groups.forEach((group) => {
    const tabs = group.querySelectorAll('[data-part="tab"]');
    const panels = group.querySelectorAll('[data-part="panel"]');

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        const index = tab.getAttribute("data-index");

        tabs.forEach((t) => t.removeAttribute("data-selected"));
        tab.setAttribute("data-selected", "true");

        panels.forEach((p) => {
          if (p.getAttribute("data-index") === index) {
            p.removeAttribute("data-hidden");
          } else {
            p.setAttribute("data-hidden", "true");
          }
        });
      });
    });
  });
}

const CodeGroup = {
  mounted() {
    setupCodeGroups(this.el);
  },
  updated() {
    setupCodeGroups(this.el);
  },
};

export { CodeGroup, setupCodeGroups };
