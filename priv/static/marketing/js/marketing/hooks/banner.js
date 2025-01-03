import Cookies from "https://cdn.jsdelivr.net/npm/js-cookie@3.0.5/+esm";

const CONSENT_KEY = "cookie-consent";

const CookiesBanner = {
  mounted() {
    const banner = this.el;
    const consent = Cookies.get(CONSENT_KEY);

    if (consent === undefined) {
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
    Cookies.set(CONSENT_KEY, value, { expires: 365 }); // Set cookie for 1 year
    banner.style.display = "none";
  },
};

export { CookiesBanner };
