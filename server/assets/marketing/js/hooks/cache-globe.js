// Page controller for the cache globe page (/globe). It draws nothing
// itself: the globe is the shared DitherGlobe canvas, which this hook feeds
// with serving-region markers (active when the region served downloads in
// the last five minutes), delayed estimated request origins, and an optional
// illustrative animation layer independent of measured metrics. Motion
// pauses both layers. Everything else is bookkeeping — the
// counters, the region rows (live totals never count estimated arcs),
// the status line, and the demo ticker.
// The demo uses these city-to-region shares. Live illustrative arcs use
// only the city coordinates, not these fictional regional traffic shares.
// Reported live origin shares remain backend estimates.
const ILLUSTRATIVE_ARCS_PER_SECOND = 3;
const ILLUSTRATIVE_ORIGINS = [
  { location: [37.77, -122.42], region: "us-west", share: 0.3 },
  { location: [21.31, -157.86], region: "us-west", share: 0.2 },
  { location: [61.22, -149.9], region: "us-west", share: 0.15 },
  { location: [49.28, -123.12], region: "us-west", share: 0.35 },
  { location: [19.43, -99.13], region: "us-central", share: 0.4 },
  { location: [30.27, -97.74], region: "us-central", share: 0.3 },
  { location: [39.74, -104.99], region: "us-central", share: 0.3 },
  { location: [40.71, -74.01], region: "us-east", share: 0.3 },
  { location: [4.71, -74.07], region: "us-east", share: 0.25 },
  { location: [25.76, -80.19], region: "us-east", share: 0.2 },
  { location: [47.56, -52.71], region: "us-east", share: 0.25 },
  { location: [-23.55, -46.63], region: "sa-west", share: 0.45 },
  { location: [-12.05, -77.04], region: "sa-west", share: 0.3 },
  { location: [-34.6, -58.38], region: "sa-west", share: 0.25 },
  { location: [52.52, 13.4], region: "eu-west", share: 0.25 },
  { location: [64.15, -21.94], region: "eu-west", share: 0.15 },
  { location: [6.52, 3.38], region: "eu-west", share: 0.2 },
  { location: [-26.2, 28.05], region: "eu-west", share: 0.2 },
  { location: [40.42, -3.7], region: "eu-west", share: 0.2 },
  { location: [60.17, 24.94], region: "eu-east", share: 0.25 },
  { location: [41.01, 28.98], region: "eu-east", share: 0.25 },
  { location: [30.04, 31.24], region: "eu-east", share: 0.2 },
  { location: [25.2, 55.27], region: "eu-east", share: 0.3 },
  { location: [-33.87, 151.21], region: "ap-southeast", share: 0.25 },
  { location: [35.68, 139.69], region: "ap-southeast", share: 0.25 },
  { location: [19.08, 72.88], region: "ap-southeast", share: 0.25 },
  { location: [-36.85, 174.76], region: "ap-southeast", share: 0.25 },
];

export const CacheGlobe = {
  mounted() {
    this.demo = this.el.dataset.demo === "true";
    this.snapshot = JSON.parse(this.el.dataset.snapshot);
    this.syncClock();
    this.globe = this.el.querySelector('[data-part="globe"]');
    this.motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
    this.paused = this.motionPreference.matches;
    this.listeners = new AbortController();
    const options = { signal: this.listeners.signal };

    this.el.querySelector('[data-action="motion"]').addEventListener(
      "click",
      () => {
        this.paused = !this.paused;
        this.updateMotion();
      },
      options,
    );
    this.motionPreference.addEventListener(
      "change",
      (event) => {
        this.paused = event.matches;
        this.updateMotion();
      },
      options,
    );
    const fullscreen = this.el.querySelector('[data-action="fullscreen"]');
    fullscreen.hidden = !document.fullscreenEnabled;
    fullscreen.addEventListener(
      "click",
      async () => {
        try {
          if (document.fullscreenElement) await document.exitFullscreen();
          else await this.el.requestFullscreen();
        } catch {
          fullscreen.hidden = true;
        }
      },
      options,
    );

    // Demo arrivals carry its illustrative totals forward. Live arcs estimate
    // origins and replay older windows, so must never change measured totals.
    this.globe?.addEventListener(
      "dither-globe:arrival",
      (event) => {
        const { region, weight } = event.detail;
        if (!this.demo || this.regionLive?.[region] == null) return;
        this.regionLive[region] += weight;
        this.renderRegion(region);
        this.sizeRegions();
      },
      options,
    );

    this.updateMotion();
    this.updateSnapshot();
    this.statusTimer = setInterval(() => this.updateStatus(), 5000);
    this.liveTimer = setInterval(() => this.advance(), 1000);
    if (this.demo) this.demoTimer = setInterval(() => this.updateSnapshot(), 3000);
  },

  updated() {
    this.el.dataset.paused = this.paused;
    this.syncClock();
    this.snapshot = JSON.parse(this.el.dataset.snapshot);
    this.updateSnapshot();
  },

  disconnected() {
    this.offline = true;
    this.updateStatus();
  },

  reconnected() {
    this.offline = false;
    this.updateStatus();
  },

  // Anchor playback and freshness to server time, advanced by a monotonic
  // browser clock. A kiosk's wall-clock skew or adjustment cannot skip windows.
  syncClock() {
    const source = this.el.dataset.serverNow;
    if (this.clock?.source === source) return;
    const at = Date.parse(source);
    if (Number.isFinite(at)) this.clock = { source, at, received: performance.now() };
  },

  serverNow() {
    return this.clock ? this.clock.at + performance.now() - this.clock.received : Date.now();
  },

  updateSnapshot() {
    if (this.demo) {
      this.demoTick = (this.demoTick || 0) + 1;
      const weights = [0.16, 0.09, 0.24, 0.06, 0.3, 0.08, 0.07];
      this.data = {
        ...this.snapshot,
        downloads: 1482903 + this.demoTick * 137,
        bytes: 8400000000000 + this.demoTick * 928000000,
        recent_downloads: 13720,
        breakdown: this.demoRates(),
        regions: this.snapshot.regions.map((region, index) => ({
          ...region,
          downloads: Math.round((1482903 + this.demoTick * 137) * weights[index]),
          recent_downloads: Math.round(13720 * weights[index]),
        })),
        origins: ILLUSTRATIVE_ORIGINS.map((origin) => ({
          ...origin,
          recent_downloads: Math.round(
            13720 * weights[this.snapshot.regions.findIndex((r) => r.id === origin.region)] * origin.share,
          ),
        })),
      };
    } else {
      this.data = this.snapshot;
    }
    const format = new Intl.NumberFormat(document.documentElement.lang || "en");
    this.sync();
    this.setReel(this.el.querySelector("#globe-bytes"), this.formatBytes(this.data.bytes));
    this.el.querySelector("#globe-region-count").textContent = format.format(this.data.regions.length);
    // Region cells show measured totals since midnight UTC. Only demo
    // arrivals carry them forward until the next snapshot.
    this.regionLive = {};
    for (const region of this.data.regions) {
      this.regionLive[region.id] = this.data.downloads == null ? null : region.downloads;
      this.renderRegion(region.id);
    }
    this.sizeRegions();
    this.renderBreakdown();
    this.updateStatus();
  },

  // The counter is carried forward between snapshots: the last five minutes
  // give a per-minute rate, and every second the counter advances by that
  // much, the rate easing toward each new measurement instead of jumping.
  // Snapshots land every 30 seconds. Nothing is invented:
  // the counter only ever moves at the measured rate, and a snapshot that
  // is ahead pulls it up straight away, while one that is behind lets the
  // measurement catch up rather than winding the counter back within a UTC day.
  sync() {
    const downloads = this.data.downloads;
    const rate = this.data.recent_downloads == null ? null : this.data.recent_downloads / 5;
    if (downloads == null || rate == null) {
      this.live = null;
      this.renderDigits(downloads);
      return;
    }
    const day = this.data.updated_at?.slice(0, 10);
    if (this.live?.day !== day) this.live = null;
    const now = performance.now();
    this.live = {
      day,
      value: Math.max(downloads, this.live?.value ?? 0),
      rate: this.live?.rate ?? rate,
      target: rate,
      at: now,
    };
    this.advance();
  },

  advance() {
    if (!this.live) return;
    const now = performance.now();
    const seconds = (now - this.live.at) / 1000;
    this.live.at = now;
    this.live.rate += (this.live.target - this.live.rate) * Math.min(1, 0.12 * seconds);
    this.live.value += (this.live.rate / 60) * seconds;
    this.renderDigits(Math.floor(this.live.value));
    this.pushMarkers();
  },

  // The counter: at least seven digits, zero-padded, handed to the SplitFlap
  // canvas (which lives inside a phx-update="ignore" block, so it follows
  // events rather than LiveView patches) and mirrored into the readout for
  // assistive technology. No number yet shows as zeros rather than dashes so
  // the row keeps its shape.
  renderDigits(value) {
    const digits = String(value == null ? 0 : Math.max(0, Math.round(value))).padStart(7, "0");
    const canvas = this.el.querySelector("#globe-flaps");
    if (canvas && canvas.dataset.value !== digits) {
      canvas.dataset.value = digits;
      canvas.dispatchEvent(new CustomEvent("split-flap:value", { detail: { value: digits } }));
    }
    const readout = this.el.querySelector('#globe-digits [data-part="readout"]');
    if (readout) readout.textContent = digits;
  },

  // A figure as an odometer: every digit is a clipped column holding a reel
  // of 0–9 twice over, slid to the digit on show; the other characters
  // (thousands separators, units) sit still. A rising digit rolls the reel
  // up, a falling one rolls it down, and when the reel would run off either
  // end it snaps to the equivalent position on the other copy first, without
  // a transition. Columns are rebuilt only when the figure's shape changes
  // (a new digit, a different unit), and new columns roll in from zero.
  setReel(el, text) {
    if (!el) return;
    const chars = Array.from(text);
    const shape = chars.map((char) => (/\d/.test(char) ? "#" : char)).join("");
    if (el.dataset.shape !== shape) {
      el.dataset.shape = shape;
      el.replaceChildren(
        ...chars.map((char) => {
          const column = document.createElement("span");
          column.dataset.part = "char";
          if (/\d/.test(char)) {
            column.dataset.digit = "";
            const reel = document.createElement("span");
            reel.dataset.part = "reel";
            reel.style.setProperty("--i", "0");
            for (let i = 0; i < 20; i++) {
              const glyph = document.createElement("span");
              glyph.textContent = String(i % 10);
              reel.appendChild(glyph);
            }
            column.appendChild(reel);
          } else {
            // A column of its own collapses an ordinary space to nothing.
            column.textContent = char === " " ? "\u00a0" : char;
          }
          return column;
        }),
      );
      // Let the zeros paint before rolling to the real digits.
      el.getBoundingClientRect();
    }
    const reels = el.querySelectorAll('[data-part="reel"]');
    const digits = chars.filter((char) => /\d/.test(char));
    reels.forEach((reel, index) => {
      const target = Number(digits[index]);
      const current = Number(reel.style.getPropertyValue("--i")) || 0;
      const shown = current % 10;
      let next = current;
      if (target > shown) {
        next = current + (target - shown);
        if (next >= 20) {
          this.snapReel(reel, current - 10);
          next -= 10;
        }
      } else if (target < shown) {
        next = current - (shown - target);
        if (next < 0) {
          this.snapReel(reel, current + 10);
          next += 10;
        }
      }
      // Stagger from the right so the roll ripples through the figure.
      reel.style.transitionDelay = `${(reels.length - 1 - index) * 30}ms`;
      reel.style.setProperty("--i", String(next));
    });
  },

  snapReel(reel, index) {
    reel.dataset.snap = "";
    reel.style.setProperty("--i", String(index));
    reel.getBoundingClientRect();
    delete reel.dataset.snap;
  },

  // Illustrative hit rates for the demo: each drifts a little every tick,
  // within a few points of its anchor, so the rows behave like live data.
  demoRates() {
    const anchors = { all: 54, module: 61, gradle: 34, bazel: 72 };
    this.rates ||= { ...anchors };
    for (const kind of Object.keys(anchors)) {
      const drifted = this.rates[kind] + (Math.random() - 0.5) * 3;
      this.rates[kind] = Math.max(anchors[kind] - 5, Math.min(anchors[kind] + 5, drifted));
    }
    return this.rates;
  },

  renderRegion(id) {
    const row = this.el.querySelector(`[data-region="${id}"]`);
    if (!row) return;
    const value = this.regionLive?.[id];
    const format = new Intl.NumberFormat(document.documentElement.lang || "en");
    this.setReel(row.querySelector('[data-part="value"]'), value == null ? "\u2014" : format.format(Math.round(value)));
  },

  sizeRegions() {
    const format = new Intl.NumberFormat(document.documentElement.lang || "en");
    const length = Math.max(
      1,
      ...Object.values(this.regionLive || {}).map((value) =>
        value == null ? 1 : format.format(Math.round(value)).length,
      ),
    );
    this.el.querySelector('[data-part="regions"]').style.setProperty("--count-length", String(length));
  },

  // Hit rate per cache. Missing observations keep a dash and an empty bar.
  renderBreakdown() {
    const shares = this.data.breakdown || {};
    for (const row of this.el.querySelectorAll('#globe-breakdown [data-part="row"]')) {
      const share = shares[row.dataset.kind];
      this.setReel(row.querySelector('[data-part="value"]'), share == null ? "\u2014" : `${Math.round(share)}%`);
      // 40 dots in the bar: light whole dots for the share.
      const dots = share == null ? 0 : Math.round((Math.max(0, Math.min(100, share)) / 100) * 40);
      row.style.setProperty("--dots", String(dots));
    }
  },

  formatBytes(bytes) {
    if (bytes == null) return "—";
    const units = ["byte", "kilobyte", "megabyte", "gigabyte", "terabyte", "petabyte"];
    const index = bytes > 0 ? Math.min(5, Math.floor(Math.log10(bytes) / 3)) : 0;
    return new Intl.NumberFormat(document.documentElement.lang || "en", {
      style: "unit",
      unit: units[index],
      unitDisplay: "short",
      maximumFractionDigits: 1,
    }).format(bytes / 1000 ** index);
  },

  updateStatus() {
    const status = this.el.querySelector("#globe-status");
    const updated = Date.parse(this.snapshot.updated_at);
    const observed = Date.parse(this.snapshot.observed_at);
    let state = "live";
    if (this.demo) state = "demo";
    else if (this.offline) state = "offline";
    else if (this.snapshot.status === "unavailable") state = "unavailable";
    else if (!Number.isFinite(updated) || !Number.isFinite(observed)) state = "waiting";
    // Allow minute refreshes, bounded queries and the 30-second web poll.
    else if (this.serverNow() - updated > 180000) state = "stale";
    else if (this.serverNow() - observed > 300000 && !this.data?.origins?.some((origin) => this.originRate(origin) > 0))
      state = "idle";
    status.dataset.state = state;
    this.active = state === "live" || state === "demo";
    for (const label of status.querySelectorAll("[data-status]")) label.hidden = label.dataset.status !== state;
    for (const region of this.data?.regions || []) {
      const row = this.el.querySelector(`[data-region="${region.id}"]`);
      if (row) row.dataset.active = this.active && region.recent_downloads > 0;
    }
    this.pushMarkers();
  },

  originRate(origin) {
    if (this.demo) return origin.recent_downloads / 300;
    const delay = origin.playback_delay_seconds ?? this.data.playback_delay_seconds;
    const at = this.serverNow() - delay * 1000;
    const start = Date.parse(origin.window_start);
    return at >= start && at < start + origin.window_seconds * 1000 ? origin.downloads / origin.window_seconds : 0;
  },

  // Region coordinates are [lat, lon] in the snapshot. The list is written
  // to the canvas as well as dispatched: the DitherGlobe hook mounts after
  // this one and reads the attribute on mount, then follows the events.
  pushMarkers() {
    if (!this.globe || !this.data) return;
    const markers = this.data.regions.map((region) => ({
      id: region.id,
      lat: region.location[0],
      lon: region.location[1],
      active: this.active && region.recent_downloads > 0,
    }));
    const markerData = JSON.stringify(markers);
    if (this.globe.dataset.markers !== markerData) {
      this.globe.dataset.markers = markerData;
      this.globe.dispatchEvent(new CustomEvent("dither-globe:markers", { detail: { markers } }));
    }
    // Play complete windows behind their measured timestamps, buffered for
    // flush/refresh/poll latency. Long windows need a longer closing-time buffer.
    // Each batch emits steadily over its duration; there is no catch-up burst,
    // replay restart on a patch, or invented volume in the reported layer.
    const byRegion = Object.fromEntries(this.data.regions.map((region) => [region.id, region.location]));
    const origins = (this.data.origins || [])
      .filter((origin) => byRegion[origin.region])
      .map((origin) => {
        const rate = this.originRate(origin);
        return {
          lat: origin.location[0],
          lon: origin.location[1],
          to: { lat: byRegion[origin.region][0], lon: byRegion[origin.region][1] },
          region: origin.region,
          rate: this.active ? rate : 0,
        };
      })
      .filter((origin) => Number.isFinite(origin.rate) && origin.rate > 0);
    if (!this.demo && this.active && this.el.dataset.illustrativeArcs === "true") {
      const reportedRate = origins.reduce((sum, origin) => sum + origin.rate, 0);
      origins.push(...this.illustrativeOrigins(Math.max(0, ILLUSTRATIVE_ARCS_PER_SECOND - reportedRate)));
    }
    // DitherGlobe mounts after this hook: retain the initial origins as well
    // as dispatching updates, otherwise a fresh page waits for the next tick.
    const originData = JSON.stringify(origins);
    if (this.globe.dataset.origins !== originData) {
      this.globe.dataset.origins = originData;
      this.globe.dispatchEvent(new CustomEvent("dither-globe:origins", { detail: { origins } }));
    }
  },

  // A bounded visual baseline, not an estimate of requests or their routes.
  // Only recently serving regions receive it; global illustrative cities keep
  // some paths visible as the globe rotates, even with one active region.
  illustrativeOrigins(rate) {
    const regions = this.data.regions.filter((region) => region.recent_downloads > 0);
    const total = regions.reduce((sum, region) => sum + region.recent_downloads, 0);
    if (!(rate > 0) || !(total > 0)) return [];
    return regions.flatMap((region) =>
      ILLUSTRATIVE_ORIGINS.map((origin) => ({
        lat: origin.location[0],
        lon: origin.location[1],
        to: { lat: region.location[0], lon: region.location[1] },
        region: region.id,
        rate: (rate * region.recent_downloads) / total / ILLUSTRATIVE_ORIGINS.length,
        illustrative: true,
      })),
    );
  },

  updateMotion() {
    this.el.dataset.paused = this.paused;
    this.el.querySelector('[data-action="motion"]').setAttribute("aria-pressed", String(this.paused));
    for (const label of this.el.querySelectorAll("[data-motion]")) {
      label.hidden = label.dataset.motion === (this.paused ? "pause" : "resume");
    }
    if (!this.globe) return;
    this.globe.dataset.paused = String(this.paused);
    this.globe.dispatchEvent(new CustomEvent("dither-globe:motion", { detail: { paused: this.paused } }));
  },

  destroyed() {
    clearInterval(this.statusTimer);
    clearInterval(this.liveTimer);
    clearInterval(this.demoTimer);
    this.listeners.abort();
  },
};
