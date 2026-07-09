function requestFullscreen(element) {
  if (element.requestFullscreen) return element.requestFullscreen();
  if (element.webkitRequestFullscreen) return Promise.resolve(element.webkitRequestFullscreen());

  return Promise.reject(new Error("Fullscreen API is not available"));
}

function exitFullscreen() {
  if (document.exitFullscreen) return document.exitFullscreen();
  if (document.webkitExitFullscreen) return Promise.resolve(document.webkitExitFullscreen());

  return Promise.reject(new Error("Fullscreen API is not available"));
}

function fullscreenElement() {
  return document.fullscreenElement || document.webkitFullscreenElement;
}

function fullscreenSupported(element) {
  if (document.fullscreenEnabled === false || document.webkitFullscreenEnabled === false) {
    return false;
  }

  return Boolean(element?.requestFullscreen || element?.webkitRequestFullscreen);
}

export default {
  mounted() {
    this.button = this.el.matches("[data-fullscreen-toggle]")
      ? this.el
      : this.el.querySelector("[data-fullscreen-toggle]");
    this.target = document.querySelector(this.el.dataset.fullscreenTarget) || this.el;
    this.label = this.button?.querySelector("span");
    this.enterLabel =
      this.button?.dataset.fullscreenEnterLabel ||
      this.button?.getAttribute("aria-label") ||
      "Full screen";
    this.exitLabel = this.button?.dataset.fullscreenExitLabel || "Exit full screen";
    this.onClick = () => this.toggle();
    this.onFullscreenChange = () => this.sync();

    if (!fullscreenSupported(this.target)) {
      this.disable();
      return;
    }

    this.button?.addEventListener("click", this.onClick);
    document.addEventListener("fullscreenchange", this.onFullscreenChange);
    document.addEventListener("webkitfullscreenchange", this.onFullscreenChange);
    this.sync();
  },

  destroyed() {
    this.button?.removeEventListener("click", this.onClick);
    document.removeEventListener("fullscreenchange", this.onFullscreenChange);
    document.removeEventListener("webkitfullscreenchange", this.onFullscreenChange);
  },

  toggle() {
    const active = fullscreenElement() === this.target;
    const action = active ? exitFullscreen() : requestFullscreen(this.target);

    action.catch(() => {
      this.el.dataset.fullscreenUnsupported = "true";
      this.button?.setAttribute("disabled", "");
    });
  },

  sync() {
    const active = fullscreenElement() === this.target;
    const label = active ? this.exitLabel : this.enterLabel;

    this.el.dataset.fullscreen = active ? "active" : "idle";
    this.button?.setAttribute("aria-pressed", active ? "true" : "false");
    this.button?.setAttribute("aria-label", label);
    if (this.label) this.label.textContent = label;
  },

  disable() {
    this.el.dataset.fullscreen = "idle";
    this.el.dataset.fullscreenUnsupported = "true";
    this.button?.setAttribute("aria-pressed", "false");
    this.button?.setAttribute("disabled", "");
  },
};
