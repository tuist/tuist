// Page controller for the cache globe page (/globe). It draws nothing
// itself: the globe is the shared DitherGlobe canvas, which this hook feeds
// with serving-region markers (active when the region served downloads in
// the last five minutes) and holds when motion is paused. Everything else
// is bookkeeping — the counters, the region rows, the status line, and the
// demo ticker.
export const CacheGlobe = {
  mounted() {
    this.demo = this.el.dataset.demo === "true";
    this.snapshot = JSON.parse(this.el.dataset.snapshot);
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

    this.updateMotion();
    this.updateSnapshot();
    this.statusTimer = setInterval(() => this.updateStatus(), 5000);
    if (this.demo) this.demoTimer = setInterval(() => this.updateSnapshot(), 3000);
  },

  updated() {
    this.el.dataset.paused = this.paused;
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

  updateSnapshot() {
    if (this.demo) {
      this.demoTick = (this.demoTick || 0) + 1;
      const weights = [0.19, 0.28, 0.36, 0.12, 0.05];
      this.data = {
        ...this.snapshot,
        downloads: 1482903 + this.demoTick * 137,
        bytes: 8400000000000 + this.demoTick * 928000000,
        recent_downloads: 13720,
        regions: this.snapshot.regions.map((region, index) => ({
          ...region,
          downloads: Math.round((1482903 + this.demoTick * 137) * weights[index]),
          recent_downloads: Math.round(13720 * weights[index]),
        })),
      };
    } else {
      this.data = this.snapshot;
    }
    const format = new Intl.NumberFormat(document.documentElement.lang || "en");
    this.el.querySelector("#globe-total").textContent =
      this.data.downloads == null ? "—" : format.format(this.data.downloads);
    this.el.querySelector("#globe-recent").textContent =
      this.data.recent_downloads == null ? "—" : format.format(this.data.recent_downloads);
    this.el.querySelector("#globe-bytes").textContent = this.formatBytes(this.data.bytes);
    const maximum = Math.max(1, ...this.data.regions.map((region) => region.recent_downloads));
    for (const region of this.data.regions) {
      const row = this.el.querySelector(`[data-region="${region.id}"]`);
      if (!row) continue;
      row.querySelector('[data-part="value"]').textContent =
        this.data.downloads == null ? "—" : format.format(region.recent_downloads);
      // The bar shows relative regional volume, not an invented time series.
      row.style.setProperty("--fill", `${(100 * region.recent_downloads) / maximum}%`);
    }
    this.updateStatus();
  },

  formatBytes(bytes) {
    if (bytes == null) return "—";
    const units = ["byte", "kilobyte", "megabyte", "gigabyte", "terabyte", "petabyte"];
    const index = bytes > 0 ? Math.min(5, Math.floor(Math.log10(bytes) / 3)) : 0;
    return new Intl.NumberFormat(document.documentElement.lang || "en", {
      style: "unit",
      unit: units[index],
      unitDisplay: "long",
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
    else if (Date.now() - updated > 90000) state = "stale";
    else if (Date.now() - observed > 300000) state = "idle";
    status.dataset.state = state;
    this.active = state === "live" || state === "demo";
    for (const label of status.querySelectorAll("[data-status]")) label.hidden = label.dataset.status !== state;
    for (const region of this.data?.regions || []) {
      const row = this.el.querySelector(`[data-region="${region.id}"]`);
      if (row) row.dataset.active = this.active && region.recent_downloads > 0;
    }
    this.pushMarkers();
  },

  // Region coordinates are [lat, lon] in the snapshot. The list is written
  // to the canvas as well as dispatched: the DitherGlobe hook mounts after
  // this one and reads the attribute on mount, then follows the events.
  pushMarkers() {
    if (!this.globe || !this.data) return;
    const markers = this.data.regions.map((region) => ({
      lat: region.location[0],
      lon: region.location[1],
      active: this.active && region.recent_downloads > 0,
    }));
    this.globe.dataset.markers = JSON.stringify(markers);
    this.globe.dispatchEvent(new CustomEvent("dither-globe:markers", { detail: { markers } }));
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
    clearInterval(this.demoTimer);
    this.listeners.abort();
  },
};
