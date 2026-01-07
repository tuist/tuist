const OAuthPopup = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      const url = this.el.getAttribute("href") || this.el.dataset.url;
      const width = 600;
      const height = 700;
      const left = window.screenX + (window.outerWidth - width) / 2;
      const top = window.screenY + (window.outerHeight - height) / 2;
      window.open(
        url,
        "oauth_popup",
        `width=${width},height=${height},left=${left},top=${top},popup=1`
      );
    });
  },
};

export default OAuthPopup;
