// Ceiling on how long we wait for Cloudflare's api.js to load before we
// give up and surface an "unavailable" error to the user. 10s is well above
// a slow first-party bundle load and comfortably below the point where a
// user would refresh the page on their own.
const API_LOAD_TIMEOUT_MS = 10000;

const Turnstile = {
  mounted() {
    this.widgetId = null;
    this.timeoutHandle = null;
    this.apiListener = null;
    this.pendingSubmit = false;
    this.responseField = this.el.querySelector("[data-turnstile-response]");

    this.handleEvent("turnstile:reset", ({ id }) => {
      if (id === this.el.id) this.reset();
    });

    // Optimistic-submit gate. When the LiveView receives a `save` before the
    // widget has produced a token, it pushes this event and shows a
    // "Verifying, one moment" message. The hook remembers that intent and
    // re-fires the form's submit as soon as the token is filled in, so the
    // user never has to click again.
    this.handleEvent("turnstile:submit-when-ready", ({ id }) => {
      if (id === this.el.id) this.pendingSubmit = true;
    });

    this.notifyState("pending");
    this.waitForApi(() => this.render());
  },

  destroyed() {
    if (this.timeoutHandle) window.clearTimeout(this.timeoutHandle);
    if (this.apiListener) {
      window.removeEventListener("tuist:turnstile-api-loaded", this.apiListener);
    }
    if (this.widgetId !== null && window.turnstile) {
      try {
        window.turnstile.remove(this.widgetId);
      } catch (_e) {
        // The api.js script tears its own iframes down when the page unloads
        // and remove() throws if the widget is already gone. Ignore.
      }
    }
  },

  // Coordinate with the inline shim in app.html.heex that sits alongside the
  // `?onload=__tuistTurnstileOnLoad` script tag. If the api.js script has
  // already fired its onload before the hook mounts, the shim leaves a flag
  // we can read synchronously. Otherwise, we subscribe to the one-shot event
  // and let the shim tell us. Either way, we never call turnstile.ready(),
  // which is the combination Cloudflare's script throws on under `defer`.
  waitForApi(onReady) {
    if (window.__tuistTurnstileReady && window.turnstile) {
      onReady();
      return;
    }

    this.apiListener = () => {
      this.apiListener = null;
      if (this.timeoutHandle) {
        window.clearTimeout(this.timeoutHandle);
        this.timeoutHandle = null;
      }
      onReady();
    };
    window.addEventListener("tuist:turnstile-api-loaded", this.apiListener, { once: true });

    this.timeoutHandle = window.setTimeout(() => {
      this.timeoutHandle = null;
      if (this.apiListener) {
        window.removeEventListener("tuist:turnstile-api-loaded", this.apiListener);
        this.apiListener = null;
      }
      this.notifyState("unavailable");
    }, API_LOAD_TIMEOUT_MS);
  },

  render() {
    if (!window.turnstile) {
      this.notifyState("unavailable");
      return;
    }

    let widgetId;
    try {
      widgetId = window.turnstile.render(this.el, {
        sitekey: this.el.dataset.sitekey,
        action: this.el.dataset.action,
        "response-field": false,
        callback: (token) => {
          this.responseField.value = token;
          this.notifyState("ready");
          if (this.pendingSubmit) {
            this.pendingSubmit = false;
            const form = this.el.closest("form");
            if (form && typeof form.requestSubmit === "function") {
              form.requestSubmit();
            } else if (form) {
              form.submit();
            }
          }
        },
        "expired-callback": () => {
          this.responseField.value = "";
          this.notifyState("pending");
        },
        // A challenge that errors out is distinct from the widget never
        // loading, and we want the user to see something and be told to
        // retry rather than staring at a disabled button. This was one of
        // the silent dead ends in the 2026-09-03 outage.
        "error-callback": () => {
          this.responseField.value = "";
          this.notifyState("error");
        },
        "timeout-callback": () => {
          this.responseField.value = "";
          this.notifyState("error");
        },
      });
    } catch (_e) {
      this.notifyState("unavailable");
      return;
    }

    if (widgetId === undefined || widgetId === null) {
      this.notifyState("unavailable");
      return;
    }

    this.widgetId = widgetId;
  },

  reset() {
    if (this.responseField) this.responseField.value = "";
    // A reset always clears an outstanding auto-submit intent: the previous
    // attempt was rejected (rate limit, invalid input, expired token), so
    // re-firing the same submit as soon as a fresh token arrives would just
    // replay the same failure.
    this.pendingSubmit = false;
    this.notifyState("pending");
    if (this.widgetId !== null && window.turnstile) {
      try {
        window.turnstile.reset(this.widgetId);
      } catch (_e) {
        this.notifyState("unavailable");
      }
    }
  },

  notifyState(state) {
    this.pushEvent("turnstile_state_changed", { id: this.el.id, state });
  },
};

export default Turnstile;
