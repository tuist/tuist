// Filled-path icon morphing, ported from the flubber-style sampling approach.
// Each icon outline is sampled into point rings and the rings are matched. For
// every matched pair we measure how well a pure rotation explains the change:
// rotation-related pairs (chevron/arrow directions) rotate cleanly instead of
// flattening into a blob, genuinely different shapes fall back to point
// morphing, and in-between pairs blend the two. Points are then tweened with a
// critically-damped spring. The animation only runs while a transition is in
// flight and then stops, so idle cost is zero.

const N = 96;
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

// Find the alignment (cyclic offset + optional reversed traversal) whose
// correspondence is best explained by a pure rotation — i.e. maximizes the
// rotational correlation |Σ a·b , Σ a×b|. Reversal is allowed only for a
// single hole-free loop (winding is free under nonzero fill) and lets a shape
// align with its mirror. Returns the offset, whether reversed, and W,Z so the
// caller can read off the angle and how well rotation explains the pair.
function alignByRotation(avecs, bvecs, allowReverse) {
  let best = { off: 0, rev: false, mag: -1, w: 1, z: 0 };
  const search = (bv, rev) => {
    for (let off = 0; off < N; off++) {
      let w = 0;
      let z = 0;
      for (let k = 0; k < N; k++) {
        const a = avecs[k];
        const b = bv[(k + off) % N];
        w += a[0] * b[0] + a[1] * b[1];
        z += a[0] * b[1] - a[1] * b[0];
      }
      const mag = w * w + z * z;
      if (mag > best.mag) best = { off, rev, mag, w, z };
    }
  };
  search(bvecs, false);
  if (allowReverse) search(bvecs.slice().reverse(), true);
  return best;
}

// TAU: residual-as-fraction-of-size above which we stop rotating and just
// morph the points. Lower = rotate only very-close pairs; higher = rotate
// more eagerly. ~0.3 means "if a rotation leaves <30% mismatch, rotate."
const TAU = 0.3;

// Adaptive hybrid: for each matched ring pair, measure how well a rotation
// explains the transform. Rotation-related pairs (chevron/arrow directions)
// rotate cleanly — no flatten; genuinely different shapes fall back to point
// morphing; in-between pairs blend (rotate partially, morph the rest).
function buildMorph(A0, B0) {
  const R = Math.max(A0.length, B0.length);
  const A = pad(A0, R, iconCentroid(A0));
  const B = matchRings(A, pad(B0, R, iconCentroid(B0)));
  const allowReverse = R === 1; // single hole-free loop — winding is free
  const rings = [];
  for (let i = 0; i < R; i++) {
    const a = A[i];
    const braw = B[i];
    const cA = cOf(a);
    const cB = cOf(braw);
    const avecs = new Array(N);
    const bvecs = new Array(N);
    let aa = 0;
    let bb = 0;
    for (let k = 0; k < N; k++) {
      avecs[k] = [a[k][0] - cA[0], a[k][1] - cA[1]];
      bvecs[k] = [braw[k][0] - cB[0], braw[k][1] - cB[1]];
      aa += avecs[k][0] * avecs[k][0] + avecs[k][1] * avecs[k][1];
      bb += bvecs[k][0] * bvecs[k][0] + bvecs[k][1] * bvecs[k][1];
    }
    let theta = 0;
    let bopt = bvecs;
    if (aa > 1e-6 && bb > 1e-6) {
      const al = alignByRotation(avecs, bvecs, allowReverse);
      const src = al.rev ? bvecs.slice().reverse() : bvecs;
      bopt = new Array(N);
      for (let k = 0; k < N; k++) bopt[k] = src[(k + al.off) % N];
      const fullTheta = Math.atan2(al.z, al.w);
      const resAfterRot = Math.max(0, aa + bb - 2 * Math.sqrt(al.mag));
      const norm = resAfterRot / (aa + bb); // 0 = pure rotation
      const rigid = Math.max(0, Math.min(1, 1 - norm / TAU));
      theta = fullTheta * rigid; // full rotation when rigid→1
    } else {
      // one side is essentially a point (grow/shrink): no rotation
      bopt = bvecs;
    }
    const co = Math.cos(theta);
    const si = Math.sin(theta);
    const res = new Array(N);
    for (let k = 0; k < N; k++) {
      const ax = avecs[k][0];
      const ay = avecs[k][1];
      const rx = co * ax - si * ay;
      const ry = si * ax + co * ay;
      res[k] = [bopt[k][0] - rx, bopt[k][1] - ry]; // leftover after rotation
    }
    rings.push({ a: avecs, cA, cB, theta, res });
  }
  return rings;
}

// point positions at progress t: size-preserving rotation + point residual
function ringsAt(descs, t) {
  return descs.map((r) => {
    const ang = r.theta * t;
    const co = Math.cos(ang);
    const si = Math.sin(ang);
    const cx = r.cA[0] + (r.cB[0] - r.cA[0]) * t;
    const cy = r.cA[1] + (r.cB[1] - r.cA[1]) * t;
    const out = new Array(N);
    for (let i = 0; i < N; i++) {
      const ax = r.a[i][0];
      const ay = r.a[i][1];
      const rx = co * ax - si * ay;
      const ry = si * ax + co * ay;
      out[i] = [cx + rx + t * r.res[i][0], cy + ry + t * r.res[i][1]];
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

/**
 * Phoenix LiveView Hook that morphs an icon between two shapes when the
 * `data-state` of a watched ancestor changes.
 *
 * Expected dataset on the host `<svg>`:
 *   data-morph-from   path `d` rendered when inactive (also the initial shape)
 *   data-morph-to     path `d` morphed into when active
 *   data-morph-active data-state value that means "active" (default "open")
 *   data-morph-watch  optional CSS selector for the watched element
 *                     (defaults to the closest `[data-part="trigger"]`)
 */
export default {
  mounted() {
    this.pathEl = this.el.querySelector("path");
    this.fromD = this.el.dataset.morphFrom;
    this.toD = this.el.dataset.morphTo;
    if (!this.pathEl || !this.fromD || !this.toD) return;

    this.activeState = this.el.dataset.morphActive || "open";
    this.fromRings = ringsFor(this.fromD);
    this.toRings = ringsFor(this.toD);
    this.disp = null;
    this.anim = null;
    this.raf = 0;
    this.reduced =
      typeof window !== "undefined" &&
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    this.watchSel = this.el.dataset.morphWatch || '[data-part="trigger"]';

    // Observe a stable ancestor (the LiveView hook root) rather than the
    // trigger itself. LiveView can replace the trigger element on a patch
    // (e.g. a theme switch or any dashboard update), which would silently
    // detach an observer bound directly to it and stop the morph until a full
    // page reload. The hook root is preserved across patches.
    this.rootEl =
      (this.el.parentElement && this.el.parentElement.closest("[phx-hook]")) ||
      this.el.parentElement ||
      this.el;

    this.lastActive = this.isActive();
    if (this.lastActive) {
      this.disp = copyRings(this.toRings);
      this.pathEl.setAttribute("d", ringsToPath(this.disp));
    }

    this.observer = new MutationObserver(() => this.sync());
    this.observer.observe(this.rootEl, {
      attributes: true,
      subtree: true,
      attributeFilter: ["data-state"],
    });
  },

  isActive() {
    const trigger = this.el.closest(this.watchSel);
    return !!trigger && trigger.getAttribute("data-state") === this.activeState;
  },

  sync() {
    const active = this.isActive();
    if (active === this.lastActive) return;
    this.lastActive = active;
    this.morphTo(active ? this.toRings : this.fromRings);
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
