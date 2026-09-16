// Imported only when the globe hook mounts so other marketing pages do not
// initialize a renderer or fetch the globe's map texture.
export const CacheGlobe = {
  async mounted() {
    this.disposed = false;
    this.demo = this.el.dataset.demo === "true";
    this.snapshot = JSON.parse(this.el.dataset.snapshot);
    this.visual = this.el.querySelector(".globe-visual");
    this.canvas = this.el.querySelector(".globe-canvas");
    this.overlay = this.el.querySelector(".globe-particles");
    this.context = this.overlay.getContext("2d");
    this.motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
    this.paused = this.motionPreference.matches;
    this.phi = -0.55;
    this.theta = 0.22;
    this.time = 0;
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

    this.canvas.addEventListener(
      "pointerdown",
      (event) => {
        this.dragX = event.clientX;
        this.canvas.setPointerCapture(event.pointerId);
      },
      options,
    );
    this.canvas.addEventListener(
      "pointermove",
      (event) => {
        if (this.dragX == null) return;
        this.phi += (event.clientX - this.dragX) / 250;
        this.dragX = event.clientX;
        this.renderGlobe();
      },
      options,
    );
    for (const name of ["pointerup", "pointercancel", "lostpointercapture"]) {
      this.canvas.addEventListener(
        name,
        () => {
          this.dragX = null;
        },
        options,
      );
    }
    document.addEventListener(
      "visibilitychange",
      () => {
        this.lastFrame = null;
        if (document.hidden) cancelAnimationFrame(this.frame);
        else this.startFrames();
      },
      options,
    );
    this.canvas.addEventListener(
      "webglcontextlost",
      (event) => {
        event.preventDefault();
        this.rendererUnavailable = true;
        this.el.dataset.renderer = "unavailable";
        cancelAnimationFrame(this.frame);
      },
      options,
    );
    this.canvas.addEventListener(
      "webglcontextrestored",
      () => {
        // A fresh instance rebuilds shader programs and textures after recovery.
        this.globe?.destroy();
        this.initializeGlobe();
      },
      options,
    );

    this.updateMotion();
    this.updateSnapshot();
    this.statusTimer = setInterval(() => this.updateStatus(), 5000);
    if (this.demo) this.demoTimer = setInterval(() => this.updateSnapshot(), 3000);

    try {
      const { default: createGlobe } = await import("cobe");
      if (this.disposed) return;
      this.createGlobe = createGlobe;
      this.initializeGlobe();
    } catch {
      this.rendererUnavailable = true;
      this.el.dataset.renderer = "unavailable";
    }
  },

  initializeGlobe() {
    if (!this.canvas.getContext("webgl2") && !this.canvas.getContext("webgl")) {
      this.rendererUnavailable = true;
      this.el.dataset.renderer = "unavailable";
      return;
    }
    this.rendererUnavailable = false;
    this.el.dataset.renderer = "ready";
    this.width = this.visual.clientWidth;
    this.pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
    this.globe = this.createGlobe(this.canvas, {
      width: this.width,
      height: this.width,
      devicePixelRatio: this.pixelRatio,
      phi: this.phi,
      theta: this.theta,
      dark: 1,
      diffuse: 1.5,
      mapSamples: this.width < 550 ? 24000 : 48000,
      mapBrightness: 4.2,
      mapBaseBrightness: 0.018,
      baseColor: [0.45, 0.29, 0.64],
      markerColor: [0.92, 0.74, 1],
      glowColor: [0.25, 0.12, 0.41],
      markerElevation: 0.008,
      markers: this.markers(),
    });
    this.resizeObserver?.disconnect();
    this.resizeObserver = new ResizeObserver(() => {
      this.width = this.visual.clientWidth;
      this.overlay.width = this.width * this.pixelRatio;
      this.overlay.height = this.width * this.pixelRatio;
      this.context?.setTransform(this.pixelRatio, 0, 0, this.pixelRatio, 0, 0);
      this.globe.update({ width: this.width, height: this.width });
      this.renderGlobe();
    });
    this.resizeObserver.observe(this.visual);
    this.startFrames();
  },

  updated() {
    this.el.dataset.paused = this.paused;
    if (this.globe || this.rendererUnavailable) {
      this.el.dataset.renderer = this.rendererUnavailable ? "unavailable" : "ready";
    }
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
      row.dataset.active = region.recent_downloads > 0;
      row.querySelector(".globe-region-value").textContent =
        this.data.downloads == null ? "—" : format.format(region.recent_downloads);
      // The line shows relative regional volume, not an invented time series.
      row.querySelector("path").setAttribute("d", `M0 12 H${(80 * region.recent_downloads) / maximum}`);
    }
    this.updateStatus();
    this.renderGlobe();
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
    if (this.paused) this.renderGlobe();
  },

  markers() {
    return (this.data?.regions || []).map((region) => ({
      location: region.location,
      size: region.recent_downloads > 0 && this.active ? 0.018 : 0.009,
      color: region.recent_downloads > 0 && this.active ? [0.95, 0.78, 1] : [0.35, 0.28, 0.44],
    }));
  },

  updateMotion() {
    this.el.dataset.paused = this.paused;
    this.el.querySelector('[data-action="motion"]').setAttribute("aria-pressed", String(this.paused));
    for (const label of this.el.querySelectorAll("[data-motion]")) {
      label.hidden = label.dataset.motion === (this.paused ? "pause" : "resume");
    }
    cancelAnimationFrame(this.frame);
    this.renderGlobe();
    if (!this.paused) this.startFrames();
  },

  startFrames() {
    cancelAnimationFrame(this.frame);
    if (!this.globe || this.paused || document.hidden || this.disposed) return;
    this.lastFrame = null;
    const tick = (now) => {
      const delta = this.lastFrame == null ? 0 : Math.min(now - this.lastFrame, 50);
      this.lastFrame = now;
      this.time += delta / 1000;
      if (this.dragX == null) this.phi += delta * 0.000035;
      this.renderGlobe();
      this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  },

  // Match the globe's orthographic projection so the light stays attached to
  // its serving region as the Earth rotates. Trails move radially outward;
  // they deliberately have no destination, since none is recorded.
  project(location, radius = 0.81) {
    const lat = (location[0] * Math.PI) / 180;
    const lon = (location[1] * Math.PI) / 180 - Math.PI;
    const x = -Math.cos(lat) * Math.cos(lon) * radius;
    const y = Math.sin(lat) * radius;
    const z = Math.cos(lat) * Math.sin(lon) * radius;
    const rx = Math.cos(this.phi) * x + Math.sin(this.phi) * z;
    const ry =
      Math.sin(this.phi) * Math.sin(this.theta) * x +
      Math.cos(this.theta) * y -
      Math.cos(this.phi) * Math.sin(this.theta) * z;
    const rz =
      -Math.sin(this.phi) * Math.cos(this.theta) * x +
      Math.sin(this.theta) * y +
      Math.cos(this.phi) * Math.cos(this.theta) * z;
    return { x: ((rx + 1) * this.width) / 2, y: ((1 - ry) * this.width) / 2, visible: rz > 0 };
  },

  renderGlobe() {
    if (!this.globe || !this.data || this.rendererUnavailable) return;
    this.globe.update({ phi: this.phi, theta: this.theta, markers: this.markers() });
    const ctx = this.context;
    if (!ctx) return;
    ctx.clearRect(0, 0, this.width, this.width);
    ctx.strokeStyle = "rgba(183, 136, 233, 0.10)";
    ctx.lineWidth = 0.6;
    for (let longitude = -180; longitude < 180; longitude += 30) {
      ctx.beginPath();
      let connected = false;
      for (let latitude = -90; latitude <= 90; latitude += 3) {
        const point = this.project([latitude, longitude], 0.801);
        if (point.visible) {
          if (connected) ctx.lineTo(point.x, point.y);
          else ctx.moveTo(point.x, point.y);
        }
        connected = point.visible;
      }
      ctx.stroke();
    }
    for (let latitude = -60; latitude <= 60; latitude += 30) {
      ctx.beginPath();
      let connected = false;
      for (let longitude = -180; longitude <= 180; longitude += 3) {
        const point = this.project([latitude, longitude], 0.801);
        if (point.visible) {
          if (connected) ctx.lineTo(point.x, point.y);
          else ctx.moveTo(point.x, point.y);
        }
        connected = point.visible;
      }
      ctx.stroke();
    }
    for (const [index, region] of this.data.regions.entries()) {
      const point = this.project(region.location);
      if (!point.visible) continue;
      const active = region.recent_downloads > 0 && this.active;
      const glow = ctx.createRadialGradient(point.x, point.y, 0, point.x, point.y, active ? 36 : 12);
      glow.addColorStop(0, active ? "#d8b0ffbb" : "#b190cc55");
      glow.addColorStop(1, "#aa77ff00");
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(point.x, point.y, active ? 36 : 12, 0, Math.PI * 2);
      ctx.fill();
      if (!active) continue;
      const pulse = (this.time * 0.45 + index * 0.19) % 1;
      ctx.strokeStyle = `rgba(209, 167, 255, ${(1 - pulse) * 0.65})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.ellipse(point.x, point.y, 5 + pulse * 28, 3 + pulse * 14, -0.3, 0, Math.PI * 2);
      ctx.stroke();
      for (let n = 0; n < 7; n++) {
        const progress = (this.time * 0.3 + n / 7 + index * 0.13) % 1;
        const head = this.project(region.location, 0.81 + progress * 0.25);
        const tail = this.project(region.location, 0.81 + Math.max(0, progress - 0.12) * 0.25);
        ctx.strokeStyle = `rgba(216, 181, 255, ${Math.sin(progress * Math.PI) * 0.65})`;
        ctx.lineWidth = 1.2;
        ctx.beginPath();
        ctx.moveTo(tail.x, tail.y);
        ctx.lineTo(head.x, head.y);
        ctx.stroke();
      }
    }
  },

  destroyed() {
    this.disposed = true;
    cancelAnimationFrame(this.frame);
    clearInterval(this.statusTimer);
    clearInterval(this.demoTimer);
    this.listeners.abort();
    this.resizeObserver?.disconnect();
    this.globe?.destroy();
  },
};
