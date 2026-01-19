const COOKIE_NAME = "public_project_cta_dismissed";
const COOKIE_MAX_AGE = 31536000; // 1 year in seconds

function isBannerDismissed() {
  return document.cookie.split("; ").some((c) => c.startsWith(`${COOKIE_NAME}=`));
}

function dismissBanner() {
  document.cookie = `${COOKIE_NAME}=true; path=/; SameSite=Lax; max-age=${COOKIE_MAX_AGE}`;
}

const PublicProjectCtaBanner = {
  mounted() {
    if (isBannerDismissed()) {
      this.el.setAttribute("data-dismissed", "");
      return;
    }

    this.el.addEventListener("click", (e) => {
      if (e.target.closest("[data-part='dismiss']")) {
        dismissBanner();
        this.el.setAttribute("data-dismissed", "");
      }
    });
  },
};

export default PublicProjectCtaBanner;
