// LiveView hook that fetches text attachment content from the server on the client side.
// The server determines whether to serve content inline based on the file's MIME type
// (text/* and application/json|xml are served inline, others redirect to S3).
export default {
  mounted() {
    this.loadContent();
  },

  loadContent() {
    const url = this.el.dataset.url;
    if (!url) return;

    fetch(url)
      .then((response) => {
        if (!response.ok) throw new Error("Failed to fetch");
        return response.text();
      })
      .then((text) => {
        const pre = this.el.querySelector("pre");
        if (pre) {
          pre.textContent = text;
        }
      })
      .catch(() => {
        const pre = this.el.querySelector("pre");
        if (pre) {
          pre.textContent = "Failed to load content";
        }
      });
  },
};
