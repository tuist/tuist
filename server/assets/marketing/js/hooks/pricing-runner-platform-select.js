/**
 * PricingRunnerPlatformSelect Hook
 *
 * Drives the Tuist Runners platform toggle on the pricing page — a Noora
 * button group with one item per platform. Picking a platform marks that
 * item selected and shows only its price card and machine pickers (the
 * server renders the first platform active, so the page reads fine before
 * this mounts).
 */
export const PricingRunnerPlatformSelect = {
  mounted() {
    this.items = Array.from(this.el.querySelectorAll("[data-platform-option]"));
    this.platforms = Array.from(
      this.el.closest('[data-part="runners"]')?.querySelectorAll('[data-part="platform"], [data-part="controls"]') ??
        [],
    );
    if (!this.items.length || !this.platforms.length) {
      console.error("Pricing runner platform select: no platform options found");
      return;
    }
    this.onClick = (e) => {
      const item = e.target.closest("[data-platform-option]");
      if (!item || !this.el.contains(item)) return;
      this.select(item.getAttribute("data-platform-option"));
    };
    this.el.addEventListener("click", this.onClick);
  },

  select(id) {
    for (const item of this.items) {
      const selected = item.getAttribute("data-platform-option") === id;
      item.toggleAttribute("data-selected", selected);
      item.setAttribute("aria-pressed", selected ? "true" : "false");
    }
    for (const platform of this.platforms) {
      platform.toggleAttribute("data-active", platform.getAttribute("data-platform") === id);
    }
  },

  destroyed() {
    if (this.onClick) this.el.removeEventListener("click", this.onClick);
  },
};
