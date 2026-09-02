// 5s at 50ms per retry. Long enough to cover a slow first-party bundle load,
// short enough to surface a real block (extension, corporate proxy) before
// the user hammers Enter and burns rate-limit slots on failed submits.
const MAX_RENDER_RETRIES = 100;

const Turnstile = {
  mounted() {
    this.widgetId = null;
    this.retryTimer = null;
    this.retries = 0;
    this.responseField = this.el.querySelector("[data-turnstile-response]");

    this.handleEvent("turnstile:reset", ({ id }) => {
      if (id === this.el.id) this.reset();
    });

    this.notifyState("pending");
    this.render();
  },

  destroyed() {
    if (this.retryTimer) window.clearTimeout(this.retryTimer);
    if (this.widgetId !== null && window.turnstile) window.turnstile.remove(this.widgetId);
  },

  render() {
    if (!window.turnstile) {
      if (this.retries >= MAX_RENDER_RETRIES) {
        this.notifyState("unavailable");
        return;
      }
      this.retries += 1;
      this.retryTimer = window.setTimeout(() => this.render(), 50);
      return;
    }

    window.turnstile.ready(() => {
      if (this.widgetId !== null) return;

      this.widgetId = window.turnstile.render(this.el, {
        sitekey: this.el.dataset.sitekey,
        action: this.el.dataset.action,
        "response-field": false,
        callback: (token) => {
          this.responseField.value = token;
          this.notifyState("ready");
        },
        "expired-callback": () => {
          this.responseField.value = "";
          this.notifyState("pending");
        },
        "error-callback": () => {
          this.responseField.value = "";
          this.notifyState("pending");
        },
      });
    });
  },

  reset() {
    this.responseField.value = "";
    this.notifyState("pending");
    if (this.widgetId !== null && window.turnstile) window.turnstile.reset(this.widgetId);
  },

  notifyState(state) {
    this.pushEvent("turnstile_state_changed", { id: this.el.id, state });
  },
};

export default Turnstile;
