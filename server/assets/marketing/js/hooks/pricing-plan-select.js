/**
 * PricingPlanSelect Hook
 *
 * Drives the pricing page's tab/mobile plan picker — a Noora button group
 * with one item per plan. Picking a plan marks that item selected and swaps
 * the `.active` plan everywhere it's rendered: the comparison table's
 * columns (collapsed to a single plan column below the desktop breakpoint,
 * see pricing.css) and the header-row mirror inside the sticky picker box.
 */
export const PricingPlanSelect = {
  mounted() {
    this.items = Array.from(this.el.querySelectorAll("[data-plan-option]"));
    if (!this.items.length) {
      console.error("Pricing plan select: no plan options found");
      return;
    }
    this.onClick = (e) => {
      const item = e.target.closest("[data-plan-option]");
      if (!item || !this.el.contains(item)) return;
      this.select(item.getAttribute("data-plan-option"));
    };
    this.el.addEventListener("click", this.onClick);

    // Sticky offsets, written as custom properties on the compare section:
    // the picker box pins under the navbar, whose height is measured (the
    // --sticky-top token predates this navbar), and lets go one row before
    // the table ends — the closing CTA row's height, measured too, since it
    // depends on the button and the viewport (see pricing.css).
    const compare = this.el.closest('[data-part="compare"]');
    const navbar = document.getElementById("marketing-navbar");
    const lastRow = compare?.querySelector('[data-part="table"] > [data-part="body"] > tr:last-child');
    if (compare && "ResizeObserver" in window) {
      const measure = () => {
        if (navbar) compare.style.setProperty("--pricing-sticky-top", `${navbar.offsetHeight}px`);
        if (lastRow) compare.style.setProperty("--pricing-last-row-height", `${lastRow.offsetHeight}px`);
      };
      this.observer = new ResizeObserver(measure);
      if (navbar) this.observer.observe(navbar);
      if (lastRow) this.observer.observe(lastRow);
      measure();
    }
  },

  select(index) {
    for (const item of this.items) {
      const selected = item.getAttribute("data-plan-option") === index;
      item.toggleAttribute("data-selected", selected);
      item.setAttribute("aria-pressed", selected ? "true" : "false");
    }
    document.querySelectorAll("[data-plan-index]").forEach((cell) => {
      cell.classList.toggle("active", cell.getAttribute("data-plan-index") === index);
    });
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    if (this.observer) this.observer.disconnect();
  },
};
