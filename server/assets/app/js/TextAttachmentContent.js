export default {
  mounted() {
    this.loadContent();
  },

  loadContent() {
    const url = this.el.dataset.url;
    if (!url) return;

    const inlineUrl = url + (url.includes("?") ? "&" : "?") + "inline=true";
    fetch(inlineUrl)
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
