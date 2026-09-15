let library;

function loadGoogleIdentity() {
  if (window.google?.accounts?.id) return Promise.resolve();
  if (!library) {
    library = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = "https://accounts.google.com/gsi/client";
      script.async = true;
      script.onload = resolve;
      script.onerror = () => {
        library = undefined;
        script.remove();
        reject(new Error("Google sign-in could not load"));
      };
      document.head.appendChild(script);
    });
  }
  return library;
}

export const GoogleOneTap = {
  async mounted() {
    if (!window.isSecureContext || !("IdentityCredential" in window) || window.top !== window.self) return;

    this.abortController = new AbortController();
    this.onPageHide = () => this.destroyed();
    window.addEventListener("pagehide", this.onPageHide, { once: true });

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
      const response = await fetch(this.el.dataset.startUrl, {
        method: "POST",
        credentials: "same-origin",
        headers: { "x-csrf-token": csrfToken },
        signal: this.abortController.signal,
      });
      if (!response.ok) return;
      const { client_id, nonce } = await response.json();
      if (!client_id || !nonce || this.abortController.signal.aborted || !this.el.isConnected) return;

      await loadGoogleIdentity();
      if (this.abortController.signal.aborted || !this.el.isConnected) return;

      const form = this.el.querySelector("form");
      google.accounts.id.initialize({
        client_id,
        nonce,
        auto_select: false,
        // Older Google clients require this opt-in; current clients use the browser by default.
        use_fedcm_for_prompt: true,
        callback: ({ credential }) => {
          if (!credential || this.abortController.signal.aborted || !form.isConnected) return;
          form.elements.credential.value = credential;
          form.requestSubmit();
        },
      });
      this.prompted = true;
      google.accounts.id.prompt();
    } catch {
      // Existing sign-in options remain available when One Tap cannot run.
    }
  },

  destroyed() {
    this.abortController?.abort();
    window.removeEventListener("pagehide", this.onPageHide);
    if (this.prompted) {
      google.accounts.id.cancel();
      this.prompted = false;
    }
  },
};
