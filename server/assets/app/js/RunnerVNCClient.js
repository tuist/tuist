import RFB from "@novnc/novnc";

function websocketURL(path) {
  const url = new URL(path, window.location.href);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  return url.href;
}

export default {
  mounted() {
    this.connect();
  },

  destroyed() {
    this.disconnect();
  },

  connect() {
    const path = this.el.dataset.vncPath;
    if (!path) return;

    this.el.dataset.connection = "connecting";
    this.rfb = new RFB(this.el, websocketURL(path));
    this.rfb.scaleViewport = true;
    this.rfb.resizeSession = false;
    this.rfb.clipViewport = false;
    this.rfb.dragViewport = false;
    this.rfb.focusOnClick = true;
    this.rfb.viewOnly = false;

    this.onConnect = () => {
      this.el.dataset.connection = "connected";
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
  },

  disconnect() {
    if (!this.rfb) return;

    this.rfb.removeEventListener("connect", this.onConnect);
    this.rfb.removeEventListener("disconnect", this.onDisconnect);
    this.rfb.removeEventListener("securityfailure", this.onSecurityFailure);
    this.rfb.disconnect();
    this.rfb = null;
  },
};
