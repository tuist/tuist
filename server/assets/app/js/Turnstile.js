const API_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
// Global ceiling for how long we wait between the api.js `<script>` being
// appended and its onload callback firing. Well above a slow first-party
// bundle load, comfortably below the point where a user would refresh the
// page on their own. Only relevant when the download finishes but the
// script's own initialization stalls — a network failure surfaces sooner
// through the `<script>` element's error event.
const API_LOAD_TIMEOUT_MS = 10000;

// The api.js callback name Cloudflare invokes via `?onload=`. Cloudflare's
// documented pattern for `render=explicit` under a deferred script tag,
// and the one thing that must be a shared global — `turnstile.render()`
// can't be called until the api.js callback has fired, and the callback
// only fires once for the whole page load.
const ONLOAD_CALLBACK_NAME = "__tuistTurnstileOnLoad";

// Shared, module-level load promise. Every hook mount reads it: if api.js
// is already loading (or loaded), the mount joins the existing wait rather
// than injecting a second `<script>`. Reset to null on a failed load so a
// later mount can retry from a fresh state.
let apiPromise = null;

function loadApi() {
  if (apiPromise) return apiPromise;

  if (window.turnstile) {
    apiPromise = Promise.resolve(window.turnstile);
    return apiPromise;
  }

  apiPromise = new Promise((resolve, reject) => {
    let timeoutHandle = null;
    const cleanup = () => {
      if (timeoutHandle) window.clearTimeout(timeoutHandle);
      delete window[ONLOAD_CALLBACK_NAME];
    };

    // Cloudflare's `?onload=` is what tells us api.js has finished its own
    // initialization. Using turnstile.ready() alongside `defer` is the
    // combination that threw in the 2026-09-03 outage; this pattern
    // sidesteps it entirely because the callback fires from api.js itself,
    // not from a downstream consumer.
    window[ONLOAD_CALLBACK_NAME] = () => {
      cleanup();
      resolve(window.turnstile);
    };

    const script = document.createElement("script");
    script.src = `${API_URL}&onload=${ONLOAD_CALLBACK_NAME}`;
    script.async = true;
    script.defer = true;
    script.onerror = () => {
      cleanup();
      apiPromise = null;
      reject(new Error("turnstile-api-load-failed"));
    };

    timeoutHandle = window.setTimeout(() => {
      cleanup();
      apiPromise = null;
      reject(new Error("turnstile-api-load-timeout"));
    }, API_LOAD_TIMEOUT_MS);

    document.head.appendChild(script);
  });

  return apiPromise;
}

const Turnstile = {
  mounted() {
    this.widgetId = null;
    this.pendingSubmit = false;
    this.responseField = this.el.querySelector("[data-turnstile-response]");

    this.handleEvent("turnstile:reset", ({ id }) => {
      if (id === this.el.id) this.reset();
    });

    // Optimistic-submit gate. When the LiveView receives a `save` before
    // the widget has produced a token, it pushes this event and shows a
    // "Verifying, one moment" message. The hook remembers the intent and
    // re-fires the form's submit as soon as the token is filled in, so
    // the user never has to click again.
    this.handleEvent("turnstile:submit-when-ready", ({ id }) => {
      if (id === this.el.id) this.pendingSubmit = true;
    });

    this.notifyState("pending");
    loadApi().then(
      () => this.render(),
      () => this.notifyState("unavailable"),
    );
  },

  destroyed() {
    if (this.widgetId !== null && window.turnstile) {
      try {
        window.turnstile.remove(this.widgetId);
      } catch (_e) {
        // api.js tears its own iframes down when the page unloads and
        // remove() throws if the widget is already gone. Ignore.
      }
    }
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
    // A reset always clears an outstanding auto-submit intent: the
    // previous attempt was rejected (rate limit, invalid input, expired
    // token), and re-firing the same submit as soon as a fresh token
    // arrives would just replay the same failure.
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
