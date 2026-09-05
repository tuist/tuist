/*
 * Newsletter page: submits the subscribe form in place.
 *
 * The form posts as JSON-returning multipart to /newsletter (the same
 * endpoint the legacy page used) and shows the server's message in the
 * status line under the row — success or error — instead of navigating.
 * The button is disabled while the request is in flight; a network
 * failure falls back to the translated message the form carries in
 * data-error-message.
 */
export const NewsletterForm = {
  mounted() {
    this.form = this.el;
    this.status = this.form.querySelector('[data-part="status"]');
    this.submit = this.form.querySelector('button[type="submit"]');
    this.onSubmit = (event) => this.handleSubmit(event);
    this.form.addEventListener("submit", this.onSubmit);
  },

  destroyed() {
    this.form.removeEventListener("submit", this.onSubmit);
  },

  async handleSubmit(event) {
    event.preventDefault();
    this.setStatus(null);
    this.submit.disabled = true;

    try {
      const response = await fetch(this.form.action, {
        method: "POST",
        body: new FormData(this.form),
        credentials: "same-origin",
        headers: { Accept: "application/json" },
      });
      const result = await response.json();
      this.setStatus(result.message, result.success ? "success" : "error");
      if (result.success) this.form.reset();
    } catch (_error) {
      this.setStatus(this.form.dataset.errorMessage, "error");
    } finally {
      this.submit.disabled = false;
    }
  },

  setStatus(message, status) {
    if (!this.status) return;
    if (!message) {
      this.status.hidden = true;
      this.status.textContent = "";
      delete this.status.dataset.status;
      return;
    }
    this.status.textContent = message;
    this.status.dataset.status = status;
    this.status.hidden = false;
  },
};
