/*
 * Live cache download count in the home hero eyebrow.
 *
 * The server renders the cache globe's latest snapshot (today's measured
 * download requests, the last five minutes' requests, and when it was taken)
 * into data attributes. Like the globe page's counter, this carries the count
 * forward from the recent measured rate, as an estimate between reports, and
 * applies the same freshness bounds: it only advances while the snapshot is
 * under three minutes old and its data under five, and stops at the UTC day
 * boundary.
 *
 * The homepage is publicly cached (stale-while-revalidate), so a visitor can
 * receive HTML rendered long before they load it. Freshness is therefore
 * judged against the visitor's clock rather than a server timestamp: a stale
 * snapshot from today shows its measured value without advancing, and one from
 * an earlier UTC day hides the eyebrow, since "today" would be wrong.
 *
 * The figure renders as odometer reels (lib/digit-reel.js): digits roll to
 * each new value, with a soft fade at the top and bottom of every column. A
 * visually hidden copy carries the plain number for screen readers.
 */

import { setReel } from "../lib/digit-reel.js";

const FRESH_SNAPSHOT_MS = 180000;
const FRESH_OBSERVATION_MS = 300000;
const RECENT_WINDOW_SECONDS = 300;
// Longer than a digit's roll (0.6s), so each roll settles and the figure
// rests sharp between updates instead of always being mid-roll and blurred.
const TICK_MS = 1500;

const utcDay = (ms) => new Date(ms).toISOString().slice(0, 10);

export const HomeCacheCount = {
  mounted() {
    const { downloads, recentDownloads, updatedAt, observedAt } = this.el.dataset;
    const base = Number(downloads);
    const updated = Date.parse(updatedAt);
    const observed = Date.parse(observedAt);
    const recent = Number(recentDownloads);
    this.valueEl = this.el.querySelector('[data-part="value"]');
    this.format = new Intl.NumberFormat(document.documentElement.lang || "en");
    if (!this.valueEl || !Number.isFinite(base) || !Number.isFinite(updated)) return;
    this.readout = document.createElement("span");
    this.readout.className = "sr-only";
    this.valueEl.after(this.readout);
    this.valueEl.setAttribute("aria-hidden", "true");

    const day = utcDay(updated);
    if (utcDay(Date.now()) !== day) {
      this.el.hidden = true;
      return;
    }
    this.render(base);

    const rate = Number.isFinite(recent) && recent > 0 ? recent / RECENT_WINDOW_SECONDS : 0;
    const advancing = (now) =>
      rate > 0 &&
      Number.isFinite(observed) &&
      now - updated <= FRESH_SNAPSHOT_MS &&
      now - observed <= FRESH_OBSERVATION_MS &&
      utcDay(now) === day;

    if (!advancing(Date.now())) return;

    // Once the bounds lapse the count stops where it is: it never rewinds
    // within the day, matching the globe page.
    const tick = () => {
      const now = Date.now();
      if (!advancing(now)) {
        clearInterval(this.timer);
        if (utcDay(now) !== day) this.el.hidden = true;
        return;
      }
      this.render(Math.floor(base + (rate * Math.max(0, now - updated)) / 1000));
    };
    tick();
    this.timer = setInterval(tick, TICK_MS);
  },

  destroyed() {
    clearInterval(this.timer);
  },

  render(value) {
    const text = this.format.format(value);
    if (this.readout.textContent === text) return;
    this.readout.textContent = text;
    setReel(this.valueEl, text);
  },
};
