const CONSENT_KEY = "cookie-consent";

const CookiesBanner = {
  mounted() {
    const banner = this.el;
    const consent = localStorage.getItem(CONSENT_KEY);

    if (consent === null) {
      banner.style.display = "flex";
    } else {
      banner.style.display = "none";
    }

    this.el.addEventListener("accept-cookies", (e) => {
      this.setConsent(true);
    });
  },

  setConsent(value) {
    const banner = this.el;
    localStorage.setItem(CONSENT_KEY, value);
    banner.style.display = "none";
  },
};

export { CookiesBanner };
