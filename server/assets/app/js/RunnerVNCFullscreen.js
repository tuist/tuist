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
    this.button = this.el.querySelector("[data-fullscreen-toggle]");
    this.onClick = () => this.toggle();
    this.onFullscreenChange = () => this.sync();

    if (!fullscreenSupported(this.el)) {
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
    const active = fullscreenElement() === this.el;
    const action = active ? exitFullscreen() : requestFullscreen(this.el);

    action.catch(() => {
      this.el.dataset.fullscreenUnsupported = "true";
      this.button?.setAttribute("disabled", "");
    });
  },

  sync() {
    const active = fullscreenElement() === this.el;

    this.el.dataset.fullscreen = active ? "active" : "idle";
    this.button?.setAttribute("aria-pressed", active ? "true" : "false");
  },

  disable() {
    this.el.dataset.fullscreen = "idle";
    this.el.dataset.fullscreenUnsupported = "true";
    this.button?.setAttribute("aria-pressed", "false");
    this.button?.setAttribute("disabled", "");
  },
};
