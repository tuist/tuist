import { densityLayout } from "./BuildTimelineDensity.mjs";
import { debounce, hitInLane } from "./BuildTimelineInteractions.mjs";
import { bindInspectorResize } from "./BuildTimelineResize.mjs";
import { bindScrollIndicator } from "noora";
import {
  normalizeEvents,
  timeLabel,
  clampRange,
  zoomRange,
  cursorTime,
  cursorTimeLabel,
  scrollGeometry,
  scrollStart,
  ROW_HEIGHT,
} from "./BuildTimelineModel.mjs";
import { bindPinchZoom } from "./BuildTimelineZoom.mjs";
import { bindDragFocus } from "./BuildTimelineFocus.mjs";

let nextLogRequest = 0;
let nextRangeRequest = 0;
let nextNavigationRequest = 0;

export default {
  mounted() {
    this.payload = this.el.dataset.version;
    this.abort = new AbortController();
    this.part = (part) => this.el.querySelector(`[data-part="${part}"]`);
    const signal = this.abort.signal;
    this.pushEvent("load-timeline", { version: Number(this.payload) })
      .then(({ timeline }) => {
        if (signal.aborted) return;
        if (!timeline) throw new Error("Timeline unavailable");
        this.initialize(timeline);
      })
      .catch(() => {
        if (signal.aborted) return;
        this.part("payload-loading").hidden = true;
        this.part("payload-error").hidden = false;
      });
  },

  initialize(timeline) {
    this.events = normalizeEvents(timeline.events);
    this.search = "";
    this.target = "";
    this.project = "";
    this.duration = this.events.reduce(
      (end, event) => Math.max(end, event.end),
      Math.max(timeline.duration || 0, Number(this.el.dataset.duration) || 1),
    );
    this.range = { start: 0, span: this.duration };
    this.logRequest = ++nextLogRequest;
    this.palette = null;
    this.part("payload-loading").hidden = true;
    this.part("payload-error").hidden = true;
    this.part("timeline-content").hidden = false;
    this.part("summary").hidden = false;
    this.requestLog = debounce((event, request) => this.loadLog(event, request), 150, this.abort.signal);
    this.rangeRequest = ++nextRangeRequest;
    this.requestRange = debounce(() => this.loadRange(), 150, this.abort.signal);
    this.navigationRequest = ++nextNavigationRequest;
    this.stepHandler = this.handleEvent("timeline-step", ({ request_id, step }) => {
      if (request_id !== this.navigationRequest || !step || this.abort.signal.aborted) return;
      const event = normalizeEvents([step])[0];
      this.select(event);
      this.setRange(event.start_ms - event.duration_ms * 0.1, Math.max(1, event.duration_ms * 1.2));
    });
    this.rangeHandler = this.handleEvent("timeline-range", (response) => this.receiveRange(response));
    this.logHandler = this.handleEvent("timeline-log", (response) => this.receiveLog(response));
    const on = (el, name, fn) => el.addEventListener(name, fn, { signal: this.abort.signal });
    this.part = (part) => this.el.querySelector(`[data-part="${part}"]`);
    this.control = (name) => this.el.querySelector(`[data-control="${name}"]`);
    this.scrollport = this.part("scrollport");
    this.chart = this.part("chart");
    this.resizeInspector = bindInspectorResize(this.part("inspector-divider"), {
      availableWidth: () => this.part("workspace").clientWidth,
      setWidth: (width) => this.el.style.setProperty("--timeline-inspector-width", `${width}px`),
      signal: this.abort.signal,
    });
    this.scrollIndicators = ["horizontal"].map((axis) => {
      const track = document.createElement("div");
      track.className = "noora-scroll-indicator";
      track.dataset.orientation = axis;
      track.setAttribute("aria-hidden", "true");
      const thumb = document.createElement("div");
      thumb.dataset.part = "thumb";
      track.appendChild(thumb);
      this.part("timeline-chart").appendChild(track);
      return { axis, track, ...bindScrollIndicator(this.scrollport, track, thumb, axis) };
    });
    this.cancelFocus = bindDragFocus(this.part("focus-region"), {
      geometry: () => {
        const rect = this.chart.getBoundingClientRect();
        return { ...this.range, left: rect.left + 12, width: rect.width - 24 };
      },
      preview: (range) => {
        const selection = this.part("focus-selection");
        selection.hidden = !range;
        this.focusing = !!range;
        if (!range) return;
        this.hideTooltip();
        this.hideCursor();
        selection.style.left = `${12 + (this.scrollport.clientWidth - 24) * range.left}px`;
        selection.style.width = `${(this.scrollport.clientWidth - 24) * range.width}px`;
        this.part("focus-duration").textContent = timeLabel(range.span);
      },
      focus: (range) => this.setRange(range.start, range.span),
      signal: this.abort.signal,
    });
    this.el.querySelector('[data-stat="duration"]').textContent = timeLabel(this.duration);
    this.el.querySelector('[data-stat="tasks"]').textContent = (
      timeline.total_count ?? this.events.length
    ).toLocaleString();
    this.el.querySelector('[data-stat="targets"]').textContent = (timeline.targets || []).length;
    on(this.el.querySelector('[name="timeline_target"]'), "change", (event) => {
      [this.project, this.target] =
        event.target.value && event.target.value !== "all" ? JSON.parse(event.target.value) : ["", ""];
      this.filter();
    });
    on(
      this.control("search"),
      "input",
      debounce(() => this.filter(), 150, this.abort.signal),
    );
    bindPinchZoom(
      this.part("timeline-chart"),
      (factor, event) => {
        const rect = this.chart.getBoundingClientRect();
        const anchor = (event.clientX - rect.left - 12) / Math.max(1, rect.width - 24);
        this.zoom(factor, Math.max(0, Math.min(1, anchor)));
      },
      this.abort.signal,
    );
    on(this.scrollport, "scroll", () => {
      this.hideTooltip();
      this.cancelFocus();
      if (Math.abs(this.scrollport.scrollLeft - this.lastScrollLeft) > 0.5) {
        this.range.start = scrollStart(
          this.scrollport.scrollLeft,
          this.scrollport.scrollWidth - this.scrollport.clientWidth,
          this.range,
          this.duration,
        );
        this.relayout();
      }
      this.scheduleDraw();
    });
    const resetPalette = () => {
      this.palette = null;
      this.scheduleDraw();
    };
    on(window, "changed-preferred-theme", resetPalette);
    if (document.fonts) {
      on(document.fonts, "loadingdone", resetPalette);
    }
    on(this.chart, "click", (e) => this.select(this.hit(e)));
    on(this.chart, "dblclick", (e) => this.focusStep(this.hit(e)));
    on(this.chart, "mousemove", (e) => this.hover(e));
    on(this.chart, "mouseleave", () => this.hideTooltip());
    on(this.part("focus-region"), "keydown", (e) => this.keydown(e));
    on(this.part("focus-region"), "pointermove", (e) => {
      if (e.pointerType === "touch" || this.focusing) return;
      this.cursorX = e.clientX;
      this.updateCursor();
    });
    on(this.part("focus-region"), "pointerleave", () => this.hideCursor());
    const resize = () => {
      this.resizeInspector();
      this.relayout(false);
    };
    on(window, "resize", resize);
    this.resize = new ResizeObserver(resize);
    this.resize.observe(this.el);
    this.resize.observe(this.part("timeline-chart"));
    this.resize.observe(this.scrollport);
    this.filtered = this.events;
    this.relayout(false);
  },

  updated() {
    if (this.payload !== this.el.dataset.version) {
      this.destroyed();
      this.frame = null;
      this.mounted();
    }
  },

  destroyed() {
    this.cancelFocus?.();
    this.logRequest = ++nextLogRequest;
    this.abort.abort();
    if (this.logHandler) this.removeHandleEvent(this.logHandler);
    this.logHandler = null;
    if (this.rangeHandler) this.removeHandleEvent(this.rangeHandler);
    this.rangeHandler = null;
    if (this.stepHandler) this.removeHandleEvent(this.stepHandler);
    this.stepHandler = null;
    for (const indicator of this.scrollIndicators || []) {
      indicator.destroy();
      indicator.track.remove();
    }
    this.resize?.disconnect();
    this.scrollIndicators = [];
    this.layout = null;
    cancelAnimationFrame(this.frame);
  },

  filter() {
    this.search = this.control("search").value;
    this.select(null);
    this.range = { start: 0, span: this.duration };
    this.events = [];
    this.filtered = [];
    this.relayout();
  },

  relayout(fetch = true) {
    this.cancelFocus();
    this.layout = densityLayout(this.filtered, this.range, this.scrollport.clientHeight || 480);
    for (const event of this.layout.events) {
      if (event.aggregate) event.title = `${event.count.toLocaleString()} ${this.el.dataset.stepsLabel}`;
    }
    this.part("grouped-label").hidden = !this.layout.grouped;
    this.syncScroll();
    this.part("no-matches").hidden =
      fetch || this.chart.getAttribute("aria-busy") === "true" || this.layout.events.length > 0;
    this.hideTooltip();
    if (fetch) {
      this.rangeRequest = ++nextRangeRequest;
      this.chart.setAttribute("aria-busy", "true");
      this.requestRange();
    }
    this.scheduleDraw();
  },

  loadRange() {
    const request = this.rangeRequest;
    this.part("range-error").hidden = true;
    this.pushEvent("load-timeline-range", {
      version: Number(this.payload),
      request_id: request,
      ...this.range,
      search: this.search,
      target: this.target,
      project: this.project,
    })
      .then((reply) => {
        if (reply?.error) this.receiveRange({ request_id: request, error: true });
      })
      .catch(() => this.receiveRange({ request_id: request, error: true }));
  },

  receiveRange({ request_id, timeline, error }) {
    if (this.abort.signal.aborted || request_id !== this.rangeRequest) return;
    this.chart.setAttribute("aria-busy", "false");
    this.part("range-error").hidden = !error;
    if (error) return;
    this.events = normalizeEvents(timeline.events);
    this.filtered = this.events;
    this.relayout(false);
  },

  syncScroll() {
    if (!this.layout) return;
    const availableHeight = Math.max(
      320,
      Math.min(480, window.innerHeight - this.scrollport.getBoundingClientRect().top - 32),
    );
    this.scrollport.style.height = `${availableHeight}px`;
    this.el.style.setProperty("--timeline-viewport-height", `${availableHeight}px`);
    this.part("tracks").style.height = `${availableHeight}px`;
    const geometry = scrollGeometry(this.scrollport.clientWidth, this.range, this.duration);
    this.part("tracks").style.width = `${geometry.width}px`;
    const overflow = this.scrollport.scrollWidth - this.scrollport.clientWidth;
    const remaining = this.duration - this.range.span;
    this.scrollport.scrollLeft = remaining > 0 ? (this.range.start / remaining) * overflow : 0;
    this.lastScrollLeft = this.scrollport.scrollLeft;
    for (const indicator of this.scrollIndicators) {
      indicator.update();
    }
  },

  setRange(start, span) {
    this.range = clampRange(start, span, this.duration);
    this.relayout();
  },

  focusStep(event) {
    if (!event) return;
    if (!event.aggregate) this.select(event);
    this.setRange(event.start_ms - event.duration_ms * 0.1, event.duration_ms * 1.2);
  },

  hideTooltip() {
    this.part("tooltip").hidden = true;
  },

  hideCursor() {
    this.cursorX = null;
    this.part("time-cursor").hidden = true;
  },

  updateCursor() {
    const cursor = this.part("time-cursor");
    const rect = this.chart.getBoundingClientRect();
    const position = this.cursorX - rect.left;
    cursor.hidden = this.cursorX == null || this.focusing || position < 0 || position > rect.width;
    if (cursor.hidden) return;
    const x = Math.max(12, Math.min(rect.width - 12, position));
    this.part("cursor-line").style.left = `${x}px`;
    const label = this.part("cursor-time");
    label.textContent = cursorTimeLabel(cursorTime(x, rect.width, this.range));
    label.style.left = `${Math.max(0, Math.min(rect.width - label.offsetWidth, x - label.offsetWidth / 2))}px`;
  },

  hover(pointer) {
    if (this.focusing) return;
    const event = this.hit(pointer);
    this.chart.style.cursor = event ? "pointer" : "crosshair";
    const tooltip = this.part("tooltip");
    tooltip.hidden = !event;
    if (!event) return;
    tooltip.querySelector("strong").textContent = event.title;
    tooltip.querySelector("span").textContent =
      `${[event.project, event.target].filter(Boolean).join(" / ")} · ${timeLabel(event.duration_ms)}`;
    const rect = this.part("timeline-chart").getBoundingClientRect();
    tooltip.style.left = `${Math.max(8, Math.min(pointer.clientX - rect.left + 12, rect.width - tooltip.offsetWidth - 8))}px`;
    tooltip.style.top = `${Math.max(33, pointer.clientY - rect.top - tooltip.offsetHeight - 12)}px`;
  },

  zoom(factor, anchor = 0.5) {
    const range = zoomRange(this.range, factor, anchor, this.duration);
    this.setRange(range.start, range.span);
  },

  scheduleDraw() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.draw();
    });
  },

  context(canvas, height) {
    const width = this.scrollport.clientWidth;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    const ctx = canvas.getContext("2d");
    ctx.scale(dpr, dpr);
    ctx.font = this.fonts.body;
    return { ctx, width };
  },

  colors() {
    const probe = document.createElement("span");
    this.el.append(probe);
    const color = (token) => {
      probe.style.color = `var(${token})`;
      return getComputedStyle(probe).color;
    };
    const font = (weight, size) => {
      probe.style.font = `var(--noora-font-weight-${weight}) var(--noora-font-body-${size})`;
      const style = getComputedStyle(probe);
      return `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    };
    this.fonts = { body: font("regular", "small"), label: font("medium", "small") };
    const colors = {
      compile: color("--timeline-fill-compile"),
      link: color("--timeline-fill-link"),
      script: color("--timeline-fill-script"),
      resource: color("--timeline-fill-resource"),
      other: color("--timeline-fill-other"),
      failure: color("--timeline-fill-failure"),
      labels: Object.fromEntries(
        ["compile", "link", "script", "resource", "other", "failure"].map((kind) => [
          kind,
          color(`--timeline-label-${kind}`),
        ]),
      ),
      accent: color("--noora-chart-primary"),
      text: color("--noora-surface-label-primary"),
      muted: color("--noora-surface-label-secondary"),
      border: color("--noora-surface-border-primary"),
      background: color("--noora-surface-background-primary"),
      secondary: color("--noora-surface-background-secondary"),
    };
    probe.remove();
    return colors;
  },

  draw() {
    if (!this.layout) return;
    const colors = (this.palette ||= this.colors());
    const height = this.scrollport.clientHeight;
    const { ctx, width } = this.context(this.chart, height);
    const inset = 12;
    const plotWidth = width - inset * 2;
    const x = (ms) => inset + ((ms - this.range.start) / this.range.span) * plotWidth;
    const rowHeight = this.layout.grouped ? 48 : ROW_HEIGHT;
    const gap = Math.min(2, rowHeight * 0.1);
    const barHeight = this.layout.grouped ? 24 : rowHeight - gap * 2;
    ctx.fillStyle = colors.background;
    ctx.fillRect(0, 0, width, height);
    this.drawRuler(inset, plotWidth, colors);
    ctx.strokeStyle = colors.border;
    ctx.globalAlpha = 0.45;
    const tickCount = Math.max(2, Math.min(8, Math.floor(plotWidth / 100)));
    for (let i = 0; i <= tickCount; i++) {
      const px = inset + (i / tickCount) * plotWidth;
      ctx.beginPath();
      ctx.moveTo(px, 0);
      ctx.lineTo(px, height);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
    this.rectsByLane = [];
    this.rowHeight = rowHeight;
    for (const event of this.layout.events) {
      const top = event.y + gap + (this.layout.grouped ? 18 : 0);
      const left = Math.max(inset, x(event.start_ms));
      const right = Math.min(width - inset, x(event.end));
      const barWidth = Math.min(width - inset - left, Math.max(2, right - left));
      const kind = event.status === "failure" ? "failure" : event.kind;
      const color = colors[kind];
      ctx.fillStyle = color;
      ctx.globalAlpha = this.selected && this.selected.event_id !== event.event_id ? 0.55 : 1;
      ctx.beginPath();
      ctx.roundRect(left, top, barWidth, barHeight, Math.min(3, barHeight / 2));
      ctx.fill();
      ctx.globalAlpha = 1;
      if (!event.aggregate && barWidth > 50 && barHeight >= 18) {
        ctx.fillStyle = colors.labels[kind];
        this.text(
          ctx,
          [event.target, event.title].filter(Boolean).join(" · "),
          left + 7,
          top + barHeight / 2 + 4,
          barWidth - 14,
        );
      }
      const lane = Math.round((event.y - 8) / rowHeight);
      (this.rectsByLane[lane] ||= []).push({ event, left, right: left + barWidth, top, bottom: top + barHeight });
    }
    if (this.layout.grouped) {
      ctx.fillStyle = colors.text;
      for (const [lane, kind] of this.layout.kinds.entries()) {
        const label = this.part("legend").querySelector(`[data-kind="${kind}"]`).textContent;
        ctx.fillText(label, inset, lane * 48 + 20);
      }
    }
    const cursorLabel = this.part("cursor-time");
    cursorLabel.style.backgroundColor = colors.accent;
    cursorLabel.style.color = this.barTextColor(colors.accent);
    this.updateCursor();
    this.part("range").textContent =
      `${timeLabel(this.range.start)} – ${timeLabel(this.range.start + this.range.span)}`;
  },

  barTextColor(color) {
    this.textColors ||= new Map();
    if (!this.textColors.has(color)) {
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = 1;
      const context = canvas.getContext("2d", { willReadFrequently: true });
      context.fillStyle = color;
      context.fillRect(0, 0, 1, 1);
      const channels = [...context.getImageData(0, 0, 1, 1).data].slice(0, 3).map((value) => {
        const channel = value / 255;
        return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
      });
      const luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
      this.textColors.set(color, luminance > 0.179 ? "#000000" : "#ffffff");
    }
    return this.textColors.get(color);
  },

  text(ctx, text, x, y, maxWidth) {
    ctx.save();
    ctx.beginPath();
    ctx.rect(x, y - 14, Math.max(0, maxWidth), 19);
    ctx.clip();
    ctx.fillText(text, x, y);
    ctx.restore();
  },

  drawRuler(labelWidth, plotWidth, colors) {
    const { ctx, width } = this.context(this.part("ruler"), 32);
    ctx.fillStyle = colors.background;
    ctx.fillRect(0, 0, width, 32);
    ctx.fillStyle = colors.muted;
    const tickCount = Math.max(2, Math.min(8, Math.floor(plotWidth / 100)));
    for (let i = 0; i <= tickCount; i++) {
      ctx.textAlign = i === tickCount ? "right" : "left";
      ctx.fillText(
        timeLabel(this.range.start + (i / tickCount) * this.range.span),
        labelWidth + (i / tickCount) * plotWidth,
        21,
      );
    }
  },

  hit(event) {
    const rect = this.chart.getBoundingClientRect();
    const x = event.clientX - rect.left,
      y = event.clientY - rect.top;
    const lane = Math.floor((y - 8) / this.rowHeight);
    return hitInLane(this.rectsByLane?.[lane], x, y);
  },

  select(event) {
    if (event?.aggregate) {
      this.focusStep(event);
      return;
    }
    this.navigationRequest = ++nextNavigationRequest;
    this.selected = event;
    const logRequest = (this.logRequest = ++nextLogRequest);
    this.hideTooltip();
    this.part("inspector").hidden = !event;
    this.part("inspector-divider").hidden = !event;
    this.part("selection").hidden = !event;
    if (event) {
      const details = {
        title: event.title,
        target: [event.project, event.target].filter(Boolean).join(" / ") || this.el.dataset.buildLabel,
        category: this.part("legend").querySelector(`[data-kind="${event.kind}"]`).textContent,
        start: timeLabel(event.start_ms),
        duration: timeLabel(event.duration_ms),
        status:
          event.status === "failure"
            ? this.part("legend").querySelector('[data-kind="failure"]').textContent
            : this.el.dataset.successLabel,
      };
      this.showLogLoading();
      this.requestLog(event, logRequest);
      for (const [key, value] of Object.entries(details))
        this.el.querySelector(`[data-detail="${key}"]`).textContent = value;
    }
    this.scheduleDraw();
  },

  showLogLoading() {
    const status = this.part("log-status");
    status.hidden = false;
    status.textContent = this.el.dataset.logLoading;
    const content = this.part("log-content");
    content.hidden = true;
    content.textContent = "";
    this.part("log-truncated").hidden = true;
  },

  loadLog(event, request) {
    if (request !== this.logRequest) return;
    const signal = this.abort.signal;
    this.pushEvent("load-timeline-log", { event_id: event.event_id, request_id: request })
      .then((reply) => {
        if (reply?.error && !signal.aborted) this.receiveLog({ request_id: request, error: true });
      })
      .catch(() => {
        if (!signal.aborted) this.receiveLog({ request_id: request, error: true });
      });
  },

  receiveLog({ request_id, log, error }) {
    if (request_id !== this.logRequest || this.abort.signal.aborted) return;
    const status = this.part("log-status");
    if (error) {
      status.textContent = this.el.dataset.logError;
      return;
    }
    const text = log?.log || "";
    const content = this.part("log-content");
    content.textContent = text;
    content.hidden = !text;
    content.scrollLeft = 0;
    status.hidden = !!text;
    status.textContent = this.el.dataset.logEmpty;
    this.part("log-truncated").hidden = !log?.log_truncated;
  },

  keydown(event) {
    if (["Home", "+", "=", "-"].includes(event.key)) {
      event.preventDefault();
      if (event.key === "Home") this.setRange(0, this.duration);
      else this.zoom(event.key === "-" ? 2 : 0.5);
      return;
    }
    if (event.key === "Enter") {
      event.preventDefault();
      this.focusStep(this.selected);
      return;
    }
    if (!["ArrowLeft", "ArrowRight", "End"].includes(event.key)) return;
    event.preventDefault();
    const request = (this.navigationRequest = ++nextNavigationRequest);
    this.pushEvent("load-timeline-step", {
      request_id: request,
      event_id: this.selected?.event_id ?? null,
      direction: event.key === "End" ? "last" : event.key === "ArrowLeft" ? "previous" : "next",
      search: this.search,
      target: this.target,
      project: this.project,
    });
  },
};
