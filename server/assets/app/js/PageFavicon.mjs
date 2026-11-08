let activeHook;
let defaultIcons;

function update(hook) {
  const status = {
    success: "success",
    failure: "failure",
    processing: "in-progress",
    in_progress: "in-progress",
  }[hook.el.dataset.faviconStatus];
  for (const { icon, attributes } of defaultIcons) {
    const href = status && icon.getAttribute(`data-favicon-${status}`);
    if (href) {
      icon.setAttribute("href", href);
      icon.setAttribute("type", "image/png");
      icon.setAttribute("sizes", "32x32");
    } else {
      restore(icon, attributes);
    }
  }
}

function restore(icon, attributes) {
  for (const [name, value] of Object.entries(attributes)) {
    if (value === null) icon.removeAttribute(name);
    else icon.setAttribute(name, value);
  }
}

export default {
  mounted() {
    defaultIcons ??= Array.from(document.querySelectorAll('link[rel="icon"]'), (icon) => ({
      icon,
      attributes: Object.fromEntries(["href", "type", "sizes"].map((name) => [name, icon.getAttribute(name)])),
    }));
    activeHook = this;
    update(this);
  },

  updated() {
    if (activeHook === this) update(this);
  },

  destroyed() {
    // A new page can mount before the previous page's hook is destroyed.
    if (activeHook !== this) return;
    activeHook = null;
    for (const { icon, attributes } of defaultIcons) restore(icon, attributes);
  },
};
