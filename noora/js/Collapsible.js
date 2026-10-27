import * as collapsible from "@zag-js/collapsible";
import {
  getBooleanOption,
  normalizeProps,
  renderPart,
  spreadProps,
} from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Collapsible extends Component {
  initMachine(context) {
    return new VanillaMachine(collapsible.machine, context);
  }

  initApi() {
    return collapsible.connect(this.machine.service, normalizeProps);
  }

  render() {
    renderPart(this.el, "root", this.api);
    renderPart(this.el, "root:content", this.api);

    const root = this.el.querySelector(":scope > [data-part='root']");
    if (!root) return;

    const content = root.querySelector(":scope > [data-part='content']");
    const trigger = [...root.querySelectorAll("[data-part='trigger']")].find(
      (t) => !content?.contains(t),
    );

    if (trigger) spreadProps(trigger, this.api.getTriggerProps());
  }
}

export default {
  mounted() {
    this.persistKey = this.el.dataset.persistKey;

    // A label click on the previous page navigates here and replaces this
    // group's DOM, so it defers its expand to us via a flag: mount closed and
    // animate open on the fresh DOM, where the animation can't be cut off.
    this.animateOpen = this.persistKey && this.flagGet();
    if (this.animateOpen) this.flagClear();

    this.collapsible = new Collapsible(this.el, this.context());
    this.collapsible.init();

    if (this.animateOpen) {
      this.openRaf = requestAnimationFrame(() => {
        this.openRaf = requestAnimationFrame(() =>
          this.collapsible.api.setOpen(true),
        );
      });
    } else if (this.persistKey && this.storageGet() == null) {
      // Seed storage with the initial (path-derived) state so auto-opened
      // groups are remembered across navigations too, not only toggled ones.
      this.storageSet(this.collapsible.api.open);
    }

    // The navigable label only opens the group (never collapses it — that's
    // the chevron's job), since clicking it also navigates to that page. When
    // opening, the animation is handed to the destination (see above) rather
    // than run here on the DOM navigation is about to discard.
    this.label = this.el.querySelector(
      ':scope > [data-part="root"] > [data-part="header"] > [data-part="link"]',
    );
    if (this.label) {
      this.onLabelClick = () => {
        if (this.collapsible.api.open) return;
        if (this.persistKey) {
          this.storageSet(true);
          this.flagSet();
        } else {
          this.collapsible.api.setOpen(true);
        }
      };
      this.label.addEventListener("click", this.onLabelClick);
    }
  },

  updated() {
    // With persistence the stored client state is authoritative, so the
    // server's path-derived `open` must not force a remembered group open or
    // closed on navigation.
    if (!this.persistKey) {
      const shouldBeOpen = getBooleanOption(this.el, "open");
      if (shouldBeOpen && !this.collapsible.api.open) {
        this.collapsible.api.setOpen(true);
      }
    }
    this.collapsible.render();
  },

  beforeDestroy() {
    cancelAnimationFrame(this.openRaf);
    this.label?.removeEventListener("click", this.onLabelClick);
    this.collapsible.destroy();
  },

  storageKey() {
    return `noora-collapsible:${this.persistKey}`;
  },

  storageGet() {
    try {
      return sessionStorage.getItem(this.storageKey());
    } catch {
      return null;
    }
  },

  storageSet(open) {
    try {
      sessionStorage.setItem(this.storageKey(), String(open));
    } catch {
      // Storage unavailable (private mode / disabled); persistence is a
      // best-effort enhancement, so silently skip it.
    }
  },

  flagKey() {
    return `noora-collapsible-anim:${this.persistKey}`;
  },

  flagGet() {
    try {
      return sessionStorage.getItem(this.flagKey()) != null;
    } catch {
      return false;
    }
  },

  flagSet() {
    try {
      sessionStorage.setItem(this.flagKey(), "1");
    } catch {
      // Best-effort; without storage the group simply opens without animating.
    }
  },

  flagClear() {
    try {
      sessionStorage.removeItem(this.flagKey());
    } catch {
      // Ignore — nothing to clear if storage is unavailable.
    }
  },

  context() {
    const stored = this.persistKey ? this.storageGet() : null;
    let defaultOpen =
      stored != null ? stored === "true" : getBooleanOption(this.el, "open");
    // Mount closed when we're about to animate open, so the expand has a
    // starting point.
    if (this.animateOpen) defaultOpen = false;
    return {
      id: this.el.id,
      disabled: getBooleanOption(this.el, "disabled"),
      defaultOpen,
      onOpenChange: (details) => {
        if (this.persistKey) this.storageSet(details.open);
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
  },
};
