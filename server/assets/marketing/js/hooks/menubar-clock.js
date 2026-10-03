/*
 * Live clock for the download page's mock macOS menu bar. Renders the
 * visitor's current date and time in the page locale, macOS style
 * ("Mon Jun 10" · "9:41 AM"), and refreshes on each minute boundary so the
 * bar never shows a stale minute. The server-rendered placeholders stay in
 * place until the hook runs (and for crawlers).
 */
export const MenubarClock = {
  mounted() {
    const locale = document.documentElement.lang || undefined;
    this.dateEl = this.el.querySelector('[data-part="date"]');
    this.timeEl = this.el.querySelector('[data-part="time"]');
    this.dateFormat = new Intl.DateTimeFormat(locale, { weekday: "short", month: "short", day: "numeric" });
    this.timeFormat = new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit" });
    this.timer = null;
    this.tick = () => {
      const now = new Date();
      // Intl inserts a comma after the weekday ("Wed, Sep 2"); macOS doesn't.
      if (this.dateEl) this.dateEl.textContent = this.dateFormat.format(now).replace(",", "");
      if (this.timeEl) this.timeEl.textContent = this.timeFormat.format(now);
      this.el.setAttribute("datetime", now.toISOString());
      const untilNextMinute = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
      this.timer = setTimeout(this.tick, untilNextMinute + 50);
    };
    this.tick();
  },

  destroyed() {
    if (this.timer) clearTimeout(this.timer);
  },
};
