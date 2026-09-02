const Turnstile = {
  mounted() {
    this.widgetId = null;
    this.retryTimer = null;
    this.responseField = this.el.querySelector("[data-turnstile-response]");

    this.handleEvent("turnstile:reset", ({ id }) => {
      if (id === this.el.id) this.reset();
    });

    this.render();
  },

  destroyed() {
    if (this.retryTimer) window.clearTimeout(this.retryTimer);
    if (this.widgetId !== null && window.turnstile) window.turnstile.remove(this.widgetId);
  },

  render() {
    if (!window.turnstile) {
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
        },
        "expired-callback": () => {
          this.responseField.value = "";
        },
        "error-callback": () => {
          this.responseField.value = "";
        },
      });
    });
  },

  reset() {
    this.responseField.value = "";
    if (this.widgetId !== null && window.turnstile) window.turnstile.reset(this.widgetId);
  },
};

export default Turnstile;
