// LiveView hook that fetches text attachment content directly from S3 using
// presigned URLs. This avoids loading potentially large text files into server
// memory — the server only generates the presigned URL (cheap), and the browser
// fetches the content directly from S3.
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
