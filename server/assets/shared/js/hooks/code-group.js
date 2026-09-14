import { copyTextToClipboard } from "../clipboard.js";
import { copySourceText, flashCopyCheck } from "./code-copy.js";

// The active tab's background is a single floating pill that slides between
// tabs. The pill is injected here (no-JS keeps the static per-tab background)
// and positioned with offset coordinates; the transition is enabled only
// after the initial position has painted (data-ready), the same gating as
// Noora's icon transition.
function setupTabPill(tabsContainer, tabs) {
  let pill = tabsContainer.querySelector('[data-part="tab-pill"]');
  if (!pill) {
    pill = document.createElement("span");
    pill.setAttribute("data-part", "tab-pill");
    pill.setAttribute("aria-hidden", "true");
    tabsContainer.prepend(pill);
  }
  tabsContainer.setAttribute("data-animated", "");

  function position() {
    const active = tabs.find((tab) => tab.getAttribute("data-selected") === "true");
    if (!active) return;
    pill.style.transform = `translate(${active.offsetLeft}px, ${active.offsetTop}px)`;
    pill.style.width = `${active.offsetWidth}px`;
    pill.style.height = `${active.offsetHeight}px`;
  }

  position();
  requestAnimationFrame(() => {
    requestAnimationFrame(() => pill.setAttribute("data-ready", ""));
  });

  // Tab widths shift when fonts finish loading or the viewport resizes.
  const observer = new ResizeObserver(position);
  tabs.forEach((tab) => observer.observe(tab));

  return position;
}

function setupCodeGroups(el) {
  const groups = el.querySelectorAll(".code-group");

  groups.forEach((group) => {
    // LiveView `updated()` re-runs this over morphdom-patched DOM where the
    // group element usually survives; without the guard every pass would
    // stack duplicate listeners and ResizeObservers on the same elements.
    if (group.dataset.codeGroupReady) return;
    group.dataset.codeGroupReady = "true";

    const tabs = Array.from(group.querySelectorAll('[data-part="tab"]'));
    const panels = group.querySelectorAll('[data-part="panel"]');
    const copyBtn = group.querySelector('[data-part="header"] > [data-part="copy"]');
    const tabsContainer = group.querySelector('[data-part="tabs"]');
    const positionPill = tabsContainer && tabs.length > 0 ? setupTabPill(tabsContainer, tabs) : null;

    function selectTab(tab) {
      const index = tab.getAttribute("data-index");

      tabs.forEach((t) => {
        t.removeAttribute("data-selected");
        t.setAttribute("aria-selected", "false");
        t.setAttribute("tabindex", "-1");
      });
      tab.setAttribute("data-selected", "true");
      tab.setAttribute("aria-selected", "true");
      tab.setAttribute("tabindex", "0");

      panels.forEach((p) => {
        if (p.getAttribute("data-index") === index) {
          p.removeAttribute("data-hidden");
        } else {
          p.setAttribute("data-hidden", "true");
        }
      });

      if (positionPill) positionPill();
    }

    tabs.forEach((tab, i) => {
      tab.setAttribute("role", "tab");
      tab.setAttribute("tabindex", i === 0 ? "0" : "-1");
      tab.setAttribute("aria-selected", tab.getAttribute("data-selected") === "true" ? "true" : "false");

      tab.addEventListener("click", () => selectTab(tab));

      tab.addEventListener("keydown", (e) => {
        let target;
        if (e.key === "ArrowRight") {
          target = tabs[(tabs.indexOf(tab) + 1) % tabs.length];
        } else if (e.key === "ArrowLeft") {
          target = tabs[(tabs.indexOf(tab) - 1 + tabs.length) % tabs.length];
        }
        if (target) {
          e.preventDefault();
          selectTab(target);
          target.focus();
        }
      });
    });

    if (copyBtn) {
      copyBtn.setAttribute("aria-label", "Copy code");
      copyBtn.setAttribute("role", "button");
      copyBtn.setAttribute("tabindex", "0");

      copyBtn.addEventListener("click", () => {
        const activePanel = group.querySelector('[data-part="panel"]:not([data-hidden="true"])');
        if (activePanel) {
          const codeBlock = activePanel.querySelector('[data-part="code"]');
          if (codeBlock) {
            copyTextToClipboard(copySourceText(activePanel) ?? codeBlock.textContent.trim())
              .then(() => flashCopyCheck(copyBtn))
              .catch((err) => console.error("Failed to copy code:", err));
          }
        }
      });

      copyBtn.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          copyBtn.click();
        }
      });
    }
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
