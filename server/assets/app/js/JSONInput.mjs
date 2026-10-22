export function enhanceJSONInput(textarea, ResizeObserverClass = globalThis.ResizeObserver) {
  let composing = false;

  const refresh = () => {
    const wrapper = textarea.parentElement;
    const overlay = wrapper.querySelector('[data-part="overlay"]');
    const highlight = overlay?.querySelector('[data-part="highlight"]');
    const active = !composing && highlight?.dataset.source === textarea.value;

    wrapper.toggleAttribute("data-highlighted", active);
    if (!overlay) return;

    overlay.hidden = !active;
    overlay.style.width = `${textarea.clientWidth}px`;
    overlay.style.height = `${textarea.clientHeight}px`;
    // A pre omits the textarea's final empty line; scrolling it would clamp early.
    if (highlight) highlight.style.transform = `translate(${-textarea.scrollLeft}px, ${-textarea.scrollTop}px)`;
  };

  const compositionStart = () => {
    composing = true;
    refresh();
  };
  const compositionEnd = () => {
    composing = false;
    refresh();
  };

  textarea.addEventListener("input", refresh);
  textarea.addEventListener("scroll", refresh);
  textarea.addEventListener("compositionstart", compositionStart);
  textarea.addEventListener("compositionend", compositionEnd);

  const observer = ResizeObserverClass && new ResizeObserverClass(refresh);
  observer?.observe(textarea);
  refresh();

  return {
    refresh,
    destroy() {
      observer?.disconnect();
      textarea.removeEventListener("input", refresh);
      textarea.removeEventListener("scroll", refresh);
      textarea.removeEventListener("compositionstart", compositionStart);
      textarea.removeEventListener("compositionend", compositionEnd);
      textarea.parentElement.removeAttribute("data-highlighted");
      const overlay = textarea.parentElement.querySelector('[data-part="overlay"]');
      if (overlay) overlay.hidden = true;
    },
  };
}

export default {
  mounted() {
    this.jsonInput = enhanceJSONInput(this.el.querySelector("textarea"));
  },
  updated() {
    this.jsonInput?.refresh();
  },
  disconnected() {
    this.jsonInput?.destroy();
    this.jsonInput = null;
  },
  reconnected() {
    this.jsonInput?.destroy();
    this.jsonInput = enhanceJSONInput(this.el.querySelector("textarea"));
  },
  destroyed() {
    this.jsonInput?.destroy();
  },
};
