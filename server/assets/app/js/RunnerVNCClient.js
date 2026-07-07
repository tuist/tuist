import RFB from "@novnc/novnc";

const defaultAspectRatio = 16 / 10;
const minimumViewportHeight = 280;

function websocketURL(path) {
  const url = new URL(path, window.location.href);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  return url.href;
}

function fullscreenElement() {
  return document.fullscreenElement || document.webkitFullscreenElement;
}

function canvasSize(element) {
  const canvas = element.querySelector("canvas");
  if (!canvas) return null;

  const width = canvas.width;
  const height = canvas.height;
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return null;

  return { width, height };
}

export default {
  mounted() {
    this.viewport = this.el.closest('[data-part="interactive-viewport"]');
    this.desktopAspectRatio = defaultAspectRatio;
    this.onViewportResize = () => this.syncViewportSize();
    this.onFullscreenChange = () => this.syncViewportSize();

    this.resizeObserver = new ResizeObserver(this.onViewportResize);
    if (this.viewport?.parentElement) this.resizeObserver.observe(this.viewport.parentElement);
    window.addEventListener("resize", this.onViewportResize);
    document.addEventListener("fullscreenchange", this.onFullscreenChange);
    document.addEventListener("webkitfullscreenchange", this.onFullscreenChange);

    this.connect();
  },

  destroyed() {
    this.disconnect();
    this.resizeObserver?.disconnect();
    window.removeEventListener("resize", this.onViewportResize);
    document.removeEventListener("fullscreenchange", this.onFullscreenChange);
    document.removeEventListener("webkitfullscreenchange", this.onFullscreenChange);
  },

  connect() {
    const path = this.el.dataset.vncPath;
    if (!path) return;

    this.el.dataset.connection = "connecting";
    this.rfb = new RFB(this.el, websocketURL(path));
    this.rfb.background = "transparent";
    this.rfb.scaleViewport = true;
    this.rfb.resizeSession = false;
    this.rfb.clipViewport = false;
    this.rfb.dragViewport = false;
    this.rfb.focusOnClick = true;
    this.rfb.viewOnly = false;

    this.onConnect = () => {
      this.el.dataset.connection = "connected";
      this.installCanvasObserver();
      this.syncDesktopSize();
    };
    this.onDisconnect = () => {
      this.el.dataset.connection = "disconnected";
    };
    this.onSecurityFailure = () => {
      this.el.dataset.connection = "security-failure";
    };

    this.rfb.addEventListener("connect", this.onConnect);
    this.rfb.addEventListener("disconnect", this.onDisconnect);
    this.rfb.addEventListener("securityfailure", this.onSecurityFailure);
    this.installCanvasObserver();
    this.syncViewportSize();
  },

  disconnect() {
    if (!this.rfb) return;

    this.canvasObserver?.disconnect();
    cancelAnimationFrame(this.canvasObserverFrame);
    this.rfb.removeEventListener("connect", this.onConnect);
    this.rfb.removeEventListener("disconnect", this.onDisconnect);
    this.rfb.removeEventListener("securityfailure", this.onSecurityFailure);
    this.rfb.disconnect();
    this.rfb = null;
  },

  installCanvasObserver() {
    if (!this.rfb) return;
    if (this.canvasObserver) return;

    const canvas = this.el.querySelector("canvas");
    if (!canvas) {
      this.canvasObserverFrame = requestAnimationFrame(() => this.installCanvasObserver());
      return;
    }

    this.canvasObserver = new MutationObserver(() => this.syncDesktopSize());
    this.canvasObserver.observe(canvas, { attributes: true, attributeFilter: ["width", "height"] });
    this.syncDesktopSize();
  },

  syncDesktopSize() {
    const size = canvasSize(this.el);
    if (!size) {
      this.syncViewportSize();
      return;
    }

    const aspectRatio = size.width / size.height;
    this.desktopAspectRatio = aspectRatio;
    this.el.dataset.desktopWidth = size.width.toString();
    this.el.dataset.desktopHeight = size.height.toString();
    this.viewport?.style.setProperty("--runner-vnc-aspect-ratio", `${size.width} / ${size.height}`);
    this.syncViewportSize();
  },

  syncViewportSize() {
    if (!this.viewport) return;

    const parent = this.viewport.parentElement;
    const parentRect = parent?.getBoundingClientRect();
    const availableWidth = parentRect?.width || 0;
    if (availableWidth <= 0) return;

    const aspectRatio = this.desktopAspectRatio || defaultAspectRatio;
    const viewportTop = this.viewport.getBoundingClientRect().top;
    const fullscreen = Boolean(fullscreenElement());
    const heightLimit = fullscreen
      ? Math.max(minimumViewportHeight, window.innerHeight - viewportTop - 12)
      : Math.max(minimumViewportHeight, availableWidth / defaultAspectRatio);

    let width = availableWidth;
    let height = width / aspectRatio;

    if (height > heightLimit) {
      height = heightLimit;
      width = height * aspectRatio;
    }

    this.viewport.style.setProperty("--runner-vnc-width", `${Math.floor(width)}px`);
    this.viewport.style.setProperty("--runner-vnc-height", `${Math.floor(height)}px`);
  },
};
