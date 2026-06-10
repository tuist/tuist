// Animated icon transitions for the `.icon` component. Two strategies share
// one hook and one state-watcher:
//   - "morph": sample both icon outlines into point rings and tween the path
//     (flubber-style). Only valid for filled, compatible icons.
//   - "crossfade_rotate": toggle a `data-active` attribute; CSS crossfades and
//     rotates the two stacked icons. Works for any icons.
// The hook watches the `data-state` of an ancestor (the trigger by default) via
// an observer bound to the stable hook root, so it survives LiveView patches.

const N = 64;
const SVGNS = "http://www.w3.org/2000/svg";
const ringCache = new Map();

let _measure = null;
function measurer() {
  if (!_measure) {
    const svg = document.createElementNS(SVGNS, "svg");
    svg.setAttribute("width", "0");
    svg.setAttribute("height", "0");
    svg.style.cssText = "position:absolute;left:-9999px;visibility:hidden";
    const p = document.createElementNS(SVGNS, "path");
    svg.appendChild(p);
    document.body.appendChild(svg);
    _measure = p;
  }
  return _measure;
}

const splitSubpaths = (d) => d.match(/M[^M]*/g) || [d];

function sampleSubpath(d, n) {
  const p = measurer();
  p.setAttribute("d", d);
  let len = 0;
  try {
    len = p.getTotalLength();
  } catch (e) {
    len = 0;
  }
  const pts = new Array(n);
  if (len === 0) {
    let pt;
    try {
      pt = p.getPointAtLength(0);
    } catch (e) {
      pt = { x: 12, y: 12 };
    }
    for (let i = 0; i < n; i++) pts[i] = [pt.x, pt.y];
    return pts;
  }
  for (let i = 0; i < n; i++) {
    const pt = p.getPointAtLength((i / n) * len);
    pts[i] = [pt.x, pt.y];
  }
  return pts;
}

function ringsFor(d) {
  let r = ringCache.get(d);
  if (r) return r;
  r = splitSubpaths(d).map((s) => sampleSubpath(s, N));
  ringCache.set(d, r);
  return r;
}

const cOf = (ring) => {
  let x = 0;
  let y = 0;
  for (const p of ring) {
    x += p[0];
    y += p[1];
  }
  return [x / ring.length, y / ring.length];
};

const iconCentroid = (rings) => {
  let x = 0;
  let y = 0;
  for (const r of rings) {
    const c = cOf(r);
    x += c[0];
    y += c[1];
  }
  return [x / rings.length, y / rings.length];
};

function pad(rings, count, c) {
  const out = rings.map((r) => r.map((p) => p.slice()));
  while (out.length < count) {
    const deg = new Array(N);
    for (let i = 0; i < N; i++) deg[i] = c.slice();
    out.push(deg);
  }
  return out;
}

function matchRings(A, B) {
  const used = new Array(B.length).fill(false);
  const order = [];
  for (const ra of A) {
    const ca = cOf(ra);
    let best = -1;
    let bd = Infinity;
    for (let j = 0; j < B.length; j++) {
      if (used[j]) continue;
      const cb = cOf(B[j]);
      const dx = ca[0] - cb[0];
      const dy = ca[1] - cb[1];
      const dd = dx * dx + dy * dy;
      if (dd < bd) {
        bd = dd;
        best = j;
      }
    }
    used[best] = true;
    order.push(B[best]);
  }
  return order;
}

function bestAlign(avecs, bvecs, allowReverse) {
  let best = { off: 0, rev: false, cost: Infinity };
  const search = (bv, rev) => {
    for (let off = 0; off < N; off++) {
      let cost = 0;
      for (let k = 0; k < N; k++) {
        const a = avecs[k];
        const b = bv[(k + off) % N];
        const dx = a[0] - b[0];
        const dy = a[1] - b[1];
        cost += dx * dx + dy * dy;
      }
      if (cost < best.cost) best = { off, rev, cost };
    }
  };
  search(bvecs, false);
  if (allowReverse) search(bvecs.slice().reverse(), true);
  return best;
}

function buildMorph(A0, B0) {
  const R = Math.max(A0.length, B0.length);
  const A = pad(A0, R, iconCentroid(A0));
  const B = matchRings(A, pad(B0, R, iconCentroid(B0)));
  const allowReverse = R === 1;
  const rings = [];
  for (let i = 0; i < R; i++) {
    const a = A[i];
    const braw = B[i];
    const cA = cOf(a);
    const cB = cOf(braw);
    const avecs = new Array(N);
    const bvecs = new Array(N);
    let aa = 0;
    for (let k = 0; k < N; k++) {
      avecs[k] = [a[k][0] - cA[0], a[k][1] - cA[1]];
      bvecs[k] = [braw[k][0] - cB[0], braw[k][1] - cB[1]];
      aa += avecs[k][0] * avecs[k][0] + avecs[k][1] * avecs[k][1];
    }
    const al =
      aa > 1e-6
        ? bestAlign(avecs, bvecs, allowReverse)
        : { off: 0, rev: false };
    const bv = al.rev ? bvecs.slice().reverse() : bvecs;
    const res = new Array(N);
    for (let k = 0; k < N; k++) {
      const bk = bv[(k + al.off) % N];
      res[k] = [bk[0] - avecs[k][0], bk[1] - avecs[k][1]];
    }
    rings.push({ a: avecs, cA, cB, res });
  }
  return rings;
}

function ringsAt(descs, t) {
  return descs.map((r) => {
    const cx = r.cA[0] + (r.cB[0] - r.cA[0]) * t;
    const cy = r.cA[1] + (r.cB[1] - r.cA[1]) * t;
    const out = new Array(N);
    for (let i = 0; i < N; i++) {
      out[i] = [
        cx + r.a[i][0] + t * r.res[i][0],
        cy + r.a[i][1] + t * r.res[i][1],
      ];
    }
    return out;
  });
}

const r2 = (v) => Math.round(v * 100) / 100;

function ringsToPath(rings) {
  let d = "";
  for (const ring of rings) {
    d += "M" + r2(ring[0][0]) + " " + r2(ring[0][1]);
    for (let i = 1; i < ring.length; i++)
      d += "L" + r2(ring[i][0]) + " " + r2(ring[i][1]);
    d += "Z";
  }
  return d;
}

const copyRings = (rings) => rings.map((r) => r.map((p) => p.slice()));

export default {
  mounted() {
    this.transition = this.el.dataset.transition || "morph";
    this.activeState = this.el.dataset.activeState || "open";
    this.watchSel = this.el.dataset.watch || '[data-part="trigger"]';
    this.reduced =
      typeof window !== "undefined" &&
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    // Observe a stable ancestor (the LiveView hook root), not the trigger,
    // which LiveView can replace on a patch and silently detach the observer.
    this.rootEl =
      (this.el.parentElement && this.el.parentElement.closest("[phx-hook]")) ||
      this.el.parentElement ||
      this.el;

    if (this.transition === "morph") this.setupMorph();

    this.lastActive = this.isActive();
    if (this.lastActive) {
      this.el.setAttribute("data-active", "");
      if (this.transition === "morph" && this.toRings) {
        this.disp = copyRings(this.toRings);
        this.pathEl.setAttribute("d", ringsToPath(this.disp));
      }
    }

    this.observer = new MutationObserver(() => this.sync());
    this.observer.observe(this.rootEl, {
      attributes: true,
      subtree: true,
      attributeFilter: ["data-state"],
    });
  },

  setupMorph() {
    this.pathEl = this.el.querySelector("path");
    this.fromD = this.el.dataset.morphFrom;
    this.toD = this.el.dataset.morphTo;
    if (!this.pathEl || !this.fromD || !this.toD) {
      this.transition = "none";
      return;
    }
    this.fromRings = ringsFor(this.fromD);
    this.toRings = ringsFor(this.toD);
    this.disp = null;
    this.anim = null;
    this.raf = 0;
  },

  isActive() {
    const trigger = this.el.closest(this.watchSel);
    return !!trigger && trigger.getAttribute("data-state") === this.activeState;
  },

  sync() {
    const active = this.isActive();
    if (active === this.lastActive) return;
    this.lastActive = active;

    if (active) this.el.setAttribute("data-active", "");
    else this.el.removeAttribute("data-active");

    if (this.transition === "morph") {
      this.morphTo(active ? this.toRings : this.fromRings);
    }
  },

  morphTo(targetRings) {
    if (!this.pathEl) return;
    if (this.reduced) {
      this.disp = copyRings(targetRings);
      this.pathEl.setAttribute("d", ringsToPath(this.disp));
      this.anim = null;
      return;
    }
    const fromRings = this.disp || this.fromRings;
    const rings = buildMorph(copyRings(fromRings), targetRings);
    this.anim = { p: 0, v: 0, rings };
    const start = ringsAt(rings, 0);
    this.disp = start;
    this.pathEl.setAttribute("d", ringsToPath(start));
    this.loop();
  },

  loop() {
    cancelAnimationFrame(this.raf);
    let last = performance.now();
    const step = (now) => {
      const a = this.anim;
      if (!a) return;
      const dt = Math.min((now - last) / 1000, 0.032);
      last = now;
      a.v += (-650 * (a.p - 1) - 51 * a.v) * dt;
      a.p += a.v * dt;
      const done = Math.abs(a.p - 1) < 0.001 && Math.abs(a.v) < 0.02;
      const p = done ? 1 : a.p;
      const rings = ringsAt(a.rings, p);
      this.disp = rings;
      this.pathEl.setAttribute("d", ringsToPath(rings));
      if (done) {
        this.anim = null;
        return;
      }
      this.raf = requestAnimationFrame(step);
    };
    this.raf = requestAnimationFrame(step);
  },

  cleanup() {
    cancelAnimationFrame(this.raf);
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
  },

  beforeDestroy() {
    this.cleanup();
  },

  destroyed() {
    this.cleanup();
  },
};
