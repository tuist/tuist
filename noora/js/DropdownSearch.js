/**
 * Phoenix LiveView Hook for filtering dropdown items via a search input.
 * Hides items whose label does not match the typed query.
 */
export default {
  mounted() {
    this.el.addEventListener("input", () => {
      const query = this.el.value.toLowerCase();
      const content = this.el.closest('[data-part="content"]');
      if (!content) return;

      for (const item of content.querySelectorAll('[data-part="item"]')) {
        const label = (item.dataset.label || item.textContent || "").toLowerCase();
        item.style.display = label.includes(query) ? "" : "none";
      }
    });

    // Prevent the dropdown's typeahead from capturing keystrokes meant for the search input
    this.el.addEventListener("keydown", (e) => {
      e.stopPropagation();
    });

    // Clear search when dropdown closes
    const dropdown = this.el.closest('[phx-hook="NooraDropdown"]');
    if (dropdown) {
      this.observer = new MutationObserver(() => {
        const trigger = dropdown.querySelector('[data-part="trigger"]');
        if (trigger && trigger.dataset.state !== "open") {
          this.el.value = "";
          const content = this.el.closest('[data-part="content"]');
          if (!content) return;
          for (const item of content.querySelectorAll('[data-part="item"]')) {
            item.style.display = "";
          }
        }
      });
      const trigger = dropdown.querySelector('[data-part="trigger"]');
      if (trigger) {
        this.observer.observe(trigger, { attributes: true, attributeFilter: ["data-state"] });
      }
    }
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },
};
