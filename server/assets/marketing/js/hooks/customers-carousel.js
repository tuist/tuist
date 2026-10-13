/*
 * Home customers carousel: the previous/next buttons cycle the customer
 * story slides, wrapping at either end. The active slide is visible and
 * interactive; the others are inert (hidden from assistive technology and
 * out of the tab order). The card takes the active slide's brand colour
 * through --slide-color, which the stylesheet eases between slides.
 *
 * Server-rendered with the first slide active, so without this hook the
 * section still shows one complete story.
 */
export const CustomersCarousel = {
  mounted() {
    this.card = this.el.querySelector('[data-part="card"]');
    this.slides = Array.from(this.el.querySelectorAll('[data-part="slide"]'));
    if (!this.card || this.slides.length === 0) return;
    this.index = Math.max(
      0,
      this.slides.findIndex((slide) => slide.dataset.active === "true"),
    );

    this.onClick = (event) => {
      const button = event.target.closest("[data-action]");
      if (!button || !this.el.contains(button)) return;
      const step = button.dataset.action === "previous" ? -1 : button.dataset.action === "next" ? 1 : 0;
      if (step !== 0) this.show(this.index + step);
    };
    this.el.addEventListener("click", this.onClick);

    if (this.slides.length < 2) {
      for (const button of this.el.querySelectorAll("[data-action]")) button.disabled = true;
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
  },

  show(index) {
    const count = this.slides.length;
    this.index = ((index % count) + count) % count;
    this.slides.forEach((slide, i) => {
      const active = i === this.index;
      slide.dataset.active = String(active);
      slide.inert = !active;
    });
    this.card.style.setProperty("--slide-color", this.slides[this.index].dataset.color);
  },
};
