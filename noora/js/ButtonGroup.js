// <noora-button-group-indicator>: the raised tile behind a button group's
// selected item. It follows `data-selected` (set by the app, a hook, or
// LiveView) and slides to the newly selected item, so the selection moves
// across the group instead of jumping.
//
// LiveView patches reset attributes the server didn't render, so nothing
// here lives in one: the tile moves with Web Animations rather than inline
// styles, and shows itself with a custom state (`:state(active)`). A
// custom element, so the group needs no id. Until it has placed itself, the
// selected item draws its own tile (see button_group.css), so the group
// looks right before and without JavaScript.

// The tile slides for 200ms and eases out, so it starts at once and settles
// into place; the labels change color on the same timing (see
// button_group.css).
const DURATION = 200;
const EASING = "ease-out";

const reducedMotion =
  typeof window !== "undefined" &&
  window.matchMedia?.("(prefers-reduced-motion: reduce)");

// A plain base where there's no DOM, so the module can load without one.
const Base = typeof HTMLElement === "undefined" ? class {} : HTMLElement;

class NooraButtonGroupIndicator extends Base {
  // Whether the tile is placed and drawing the selection.
  get active() {
    return !!this.states?.has("active");
  }

  connectedCallback() {
    this.group = this.closest(".noora-button-group");
    // Without custom states the selected item keeps drawing its own tile.
    this.states ??= this.attachInternals?.().states;
    if (!this.group || !this.animate || !this.states) return;

    this.mutations = new MutationObserver(() => this.sync(true));
    this.mutations.observe(this.group, {
      attributes: true,
      attributeFilter: ["data-selected"],
      subtree: true,
      childList: true,
    });
    // Layout changes (fonts loading, labels changing, resizing) move the
    // selected item without a new selection: follow it without sliding.
    this.resizes = new ResizeObserver(() => this.sync(false));
    this.resizes.observe(this.group);

    // Selections made from the keyboard jump instead of sliding, so keyboard
    // users aren't kept waiting on an animation.
    this.onKey = () => (this.keyboard = true);
    this.onPointer = () => (this.keyboard = false);
    this.group.addEventListener("keydown", this.onKey);
    this.group.addEventListener("pointerdown", this.onPointer);

    // The items after this element may not be in the document yet (it comes
    // first in the group), so place the tile once they are.
    this.sync(false);
    queueMicrotask(() => this.sync(false));
  }

  disconnectedCallback() {
    this.group?.removeEventListener("keydown", this.onKey);
    this.group?.removeEventListener("pointerdown", this.onPointer);
    this.mutations?.disconnect();
    this.resizes?.disconnect();
    this.motion?.cancel();
  }

  selectedItem() {
    return this.group.querySelector(
      ":scope > .noora-button-group-item[data-selected]",
    );
  }

  // An item's box, relative to the group's padding box.
  target(item) {
    const group = this.group.getBoundingClientRect();
    const box = item.getBoundingClientRect();
    return {
      x: box.left - group.left - this.group.clientLeft,
      y: box.top - group.top - this.group.clientTop,
      width: box.width,
      height: box.height,
    };
  }

  // Where the tile is drawn right now, mid-slide included.
  current() {
    const group = this.group.getBoundingClientRect();
    const box = this.getBoundingClientRect();
    return {
      x: box.left - group.left - this.group.clientLeft,
      y: box.top - group.top - this.group.clientTop,
      width: box.width,
      height: box.height,
    };
  }

  sync(slide) {
    const item = this.selectedItem();
    if (!item) {
      this.states.delete("active");
      this.placed = null;
      return;
    }
    const to = this.target(item);

    const frame = ({ x, y, width, height }) => ({
      transform: `translate(${x}px, ${y}px)`,
      width: `${width}px`,
      height: `${height}px`,
    });
    // Only a new selection slides; the first placement, and other changes
    // to the group, settle in place.
    const moving =
      slide &&
      this.placed != null &&
      this.placed !== item &&
      !this.keyboard &&
      !reducedMotion?.matches;
    const from = moving ? this.current() : to;

    this.motion?.cancel();
    this.motion = this.animate([frame(from), frame(to)], {
      duration: moving ? DURATION : 0,
      easing: EASING,
      fill: "forwards",
    });
    this.placed = item;
    this.states.add("active");
  }
}

if (
  typeof window !== "undefined" &&
  !customElements.get("noora-button-group-indicator")
) {
  customElements.define(
    "noora-button-group-indicator",
    NooraButtonGroupIndicator,
  );
}

export default NooraButtonGroupIndicator;
