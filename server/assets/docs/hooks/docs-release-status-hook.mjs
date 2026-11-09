const DocsReleaseStatusHook = {
  mounted() {
    this.localizeTimes();
  },

  updated() {
    this.localizeTimes();
  },

  localizeTimes() {
    const formatter = new Intl.DateTimeFormat(document.documentElement.lang || "en", {
      dateStyle: "medium",
      timeStyle: "short",
    });
    this.el.querySelectorAll("[data-release-time]").forEach((element) => {
      element.textContent = formatter.format(new Date(element.dateTime));
    });
    this.el.querySelector("[data-timezone]").textContent = formatter.resolvedOptions().timeZone;
  },
};

export default DocsReleaseStatusHook;
