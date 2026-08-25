/**
 * PricingPlanSelect Hook
 *
 * Drives the pricing page's tab/mobile plan picker — a hand-rolled Noora
 * dropdown (the real component teleports its label/menu through LiveView
 * portals, which never mount on this dead-rendered page).
 *
 * Open state lives in `data-state` on the trigger, which Noora's dropdown
 * CSS keys on for the menu and the chevron indicator. Picking a plan swaps
 * the `.active` column in the comparison table, writes the plan name into
 * the trigger label, and closes the menu.
 */
export const PricingPlanSelect = {
  mounted() {
    this.trigger = this.el.querySelector('[data-part="trigger"]');
    this.content = this.el.querySelector('[data-part="content"]');
    this.indicator = this.el.querySelector('[data-part="indicator"]');
    this.label = this.el.querySelector('[data-part="label"] > span');
    this.items = Array.from(this.el.querySelectorAll('[data-part="item"]'));

    if (!this.trigger || !this.content || !this.label) {
      console.error("Pricing plan select: missing trigger, content, or label element");
      return;
    }

    this.onTriggerClick = (e) => {
      e.preventDefault();
      this.setOpen(this.trigger.getAttribute("data-state") !== "open");
    };

    this.onDocumentClick = (e) => {
      // Close on any click that lands outside the trigger and the menu
      // itself — including on the phone tray's scrim, whose click target
      // is the positioner (the ::before pseudo-element belongs to it).
      if (this.trigger.contains(e.target) || this.content.contains(e.target)) return;
      this.setOpen(false);
    };

    this.onKeydown = (e) => {
      if (e.key === "Escape") this.setOpen(false);
    };

    this.trigger.addEventListener("click", this.onTriggerClick);
    document.addEventListener("click", this.onDocumentClick);
    document.addEventListener("keydown", this.onKeydown);

    this.items.forEach((item, index) => {
      item.addEventListener("click", () => this.select(item, index));
    });
  },

  setOpen(open) {
    const state = open ? "open" : "closed";
    // Noora's CSS keys the positioner off the trigger, the menu box off
    // the content element, and the chevron swap off the indicator — zag
    // stamps data-state on all three.
    this.trigger.setAttribute("data-state", state);
    this.content.setAttribute("data-state", state);
    if (this.indicator) this.indicator.setAttribute("data-state", state);
    this.trigger.setAttribute("aria-expanded", open ? "true" : "false");
  },

  select(item, index) {
    document.querySelectorAll("[data-plan-index]").forEach((cell) => {
      cell.classList.toggle("active", cell.getAttribute("data-plan-index") === String(index));
    });
    this.label.textContent = item.getAttribute("data-label");
    this.setOpen(false);
  },

  destroyed() {
    document.removeEventListener("click", this.onDocumentClick);
    document.removeEventListener("keydown", this.onKeydown);
  },
};
