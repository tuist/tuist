/*
 * Build-system dependency graph (cache "Built for your build system"
 * card): the build system's label box in the middle with module dots
 * scattered around it, a dependency ray from the box to each dot, and
 * sparse interconnections between neighboring dots. A few random nodes
 * render purple — artifacts resolved from the cache.
 *
 * The entrance: the dots appear floating gently around the label, pull
 * INTO the center box, shoot back out to their architecture positions,
 * and only then do the lines connect — rays extending from the box,
 * interconnections after. Every cycle repeats that gesture: the dots
 * gather into the box, the label retypes to the next system
 * (typewriter-style) while they're inside, and they shoot out into a
 * freshly generated random architecture, lines reconnecting — the labels
 * cycling XCODE → GRADLE → BAZEL but every layout unique.
 *
 * Colors come from tokens on the host (re-resolved on theme change):
 *   --marketing-cache-graph-edge      dependency lines
 *   --marketing-cache-graph-node-1/2/3  the module dots' purple shades
 *   --marketing-cache-graph-cached    cache-resolved artifact dots
 *
 * Under prefers-reduced-motion the first system holds as a static,
 * fully-drawn frame.
 */

import { onThemeChange } from "../lib/theme.js";

const SYSTEMS = ["XCODE", "GRADLE", "BAZEL"];
const CYCLE_S = 7; // seconds each system holds, including its transition
const APPEAR_S = 0.3; // entrance: the floating cloud fades in
const REST_HOLD_S = 1.4; // entrance: how long the cloud floats
const GATHER_S = 0.45; // dots pull back into the floating cloud
const FLOAT_HOLD_S = 1; // reform: float by the label while it retypes
const SHOOT_S = 0.5; // dots shoot from the cloud to their positions
const LINE_LAG_S = 0.1; // beat between the dots landing and lines starting
const RAY_GROW_S = 0.5; // one ray's extension
const RAY_STAGGER_S = 0.7;
const LINK_START_S = 1.1; // interconnections begin after the rays
const LINK_STAGGER_S = 0.6;
const LINK_GROW_S = 0.35;
const ENTRANCE_S = REST_HOLD_S + SHOOT_S + LINE_LAG_S + LINK_START_S + LINK_STAGGER_S + LINK_GROW_S;
// A reform: gather to the cloud, float, shoot out, lines redraw with the
// entrance's full ray → link sequencing.
const TRANSITION_S = GATHER_S + FLOAT_HOLD_S + SHOOT_S + LINE_LAG_S + LINK_START_S + LINK_STAGGER_S + LINK_GROW_S;
// Architecture tiers around the hub; their counts sum to NODE_COUNT. The
// outer tier reaches the illustration's edges so the graph fills the box.
const TIERS = [
  { count: 10, reach: 0.45 },
  { count: 14, reach: 0.75 },
  { count: 16, reach: 1.02 },
];
const NODE_COUNT = 40;
const GRID = 22; // node positions snap to this — the circuit-board look
const CACHED_CHANCE = 0.22;

// Seeded PRNG so each system's architecture is stable across cycles,
// resizes, and visits.
function makeRng(seed) {
  let s = seed | 0 || 1;
  return () => {
    s = (Math.imul(s, 1103515245) + 12345) & 0x7fffffff;
    return s / 0x7fffffff;
  };
}

function resolveTokenColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const resolved = getComputedStyle(probe).color;
  probe.remove();
  return resolved;
}

const easeOut = (p) => 1 - Math.pow(1 - p, 3);
const smoothstep = (p) => p * p * (3 - 2 * p);
const clamp01 = (p) => Math.min(1, Math.max(0, p));

export const CacheBuildGraph = {
  mounted() {
    this.canvas = this.el.querySelector('[data-part="canvas"]');
    this.label = this.el.querySelector('[data-part="label"]');
    this.ctx = this.canvas.getContext("2d");
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.raf = null;
    this.segGraphs = new Map();

    this.resolveColors = () => {
      this.edgeColor = resolveTokenColor(this.el, "--marketing-cache-graph-edge");
      this.nodeShades = [1, 2, 3].map((n) => resolveTokenColor(this.el, `--marketing-cache-graph-node-${n}`));
      this.cachedColor = resolveTokenColor(this.el, "--marketing-cache-graph-cached");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      if (this.raf === null) this.renderStatic();
    });

    this.resize = () => {
      const rect = this.el.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.segGraphs.clear(); // layouts depend on the size
      this.rest = null;
      this.hub = null;
      if (this.raf === null) this.renderStatic();
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.el);
    this.resize();

    if (!this.reduced) {
      this.viewObserver = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) this.start();
          else this.stop();
        },
        { threshold: 0.05 },
      );
      this.viewObserver.observe(this.el);
    }
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.viewObserver) this.viewObserver.disconnect();
    this.stop();
  },

  start() {
    if (this.raf !== null) return;
    this.t0 = performance.now() - (this.tHeld || 0) * 1000;
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      const t = (now - this.t0) / 1000;
      this.tHeld = t;
      const segment = Math.floor(t / CYCLE_S);
      const index = segment % SYSTEMS.length;
      const phase = t % CYCLE_S;
      if (segment === 0 && phase < ENTRANCE_S) {
        // First cycle: the entrance — float, gather, shoot, connect.
        this.setLabel(SYSTEMS[index]);
        this.drawEntrance(this.graphFor(0), phase, t);
      } else if (segment > 0 && phase < TRANSITION_S) {
        // Reform: the dots pull back into the floating cloud by the
        // label, hover there while it retypes (typewriter), then shoot
        // out into a fresh architecture and the lines reconnect.
        const prev = (index + SYSTEMS.length - 1) % SYSTEMS.length;
        this.typeLabel(SYSTEMS[prev], SYSTEMS[index], clamp01((phase - GATHER_S) / FLOAT_HOLD_S));
        this.drawMorph(this.graphFor(segment - 1), this.graphFor(segment), phase, t);
      } else {
        this.setLabel(SYSTEMS[index]);
        this.drawSteady(this.graphFor(segment));
      }
    };
    this.raf = requestAnimationFrame(tick);
  },

  stop() {
    if (this.raf !== null) {
      cancelAnimationFrame(this.raf);
      this.raf = null;
    }
  },

  renderStatic() {
    this.setLabel(SYSTEMS[0]);
    this.drawSteady(this.graphFor(0));
  },

  setLabel(text) {
    if (this.label.textContent !== text) this.label.textContent = text;
  },

  // Typewriter swap: delete the old name character by character while the
  // dots gather, then type the new one as they shoot back out. A no-break
  // space holds the box's height at the empty midpoint.
  typeLabel(prevText, nextText, u) {
    let shown;
    if (u < 0.45) shown = prevText.slice(0, Math.ceil(prevText.length * (1 - u / 0.45)));
    else if (u < 0.55) shown = "";
    else shown = nextText.slice(0, Math.ceil(nextText.length * ((u - 0.55) / 0.45)));
    this.label.textContent = shown || " ";
  },

  // A fresh random architecture per cycle — the same segment always sees
  // the same graph (transitions read both sides), older ones are pruned.
  graphFor(segment) {
    if (!this.segGraphs.has(segment)) {
      this.segGraphs.set(segment, this.buildGraph((Math.random() * 0x7fffffff) | 0));
      for (const key of this.segGraphs.keys()) {
        if (key < segment - 1) this.segGraphs.delete(key);
      }
    }
    return this.segGraphs.get(segment);
  },

  hubGeometry() {
    if (!this.hub) {
      const labelRect = this.label.getBoundingClientRect();
      // Half-extents sit flush on the box border (+1 for its hairline),
      // so rays touch the box instead of stopping short of it.
      this.hub = {
        cx: this.w / 2,
        cy: this.h / 2,
        rx: (labelRect.width || 96) / 2 + 1,
        ry: (labelRect.height || 44) / 2 + 1,
      };
    }
    return this.hub;
  },

  // The gentle wander applied to the floating cloud, per dot.
  floatedRest(t, floatK) {
    const rest = this.restNodes();
    if (floatK <= 0) return rest;
    return rest.map((node, i) => ({
      ...node,
      x: node.x + Math.sin(t * 0.9 + i * 1.7) * 7 * floatK,
      y: node.y + Math.cos(t * 0.7 + i * 2.3) * 5 * floatK,
    }));
  },

  /* Arrange exactly NODE_COUNT dots in tiers around the label box — a
     layered architecture rather than a loose scatter: evenly spaced
     angles per tier (each tier randomly rotated, every angle jittered a
     little), radius jittered around the tier's reach, and everything
     pushed clear of the box. Sorted by angle so dots glide to their
     angular neighbor instead of crossing the hub. */
  placeNodes(rnd, look) {
    const { cx, cy, rx, ry } = this.hubGeometry();
    const spanX = this.w / 2 - 8;
    const spanY = this.h / 2 - 8;
    const nodes = [];
    for (const tier of TIERS) {
      const rotation = rnd() * Math.PI * 2;
      for (let i = 0; i < tier.count; i++) {
        const angle = rotation + (i / tier.count) * Math.PI * 2 + (rnd() - 0.5) * 0.4;
        const reach = tier.reach * (0.9 + rnd() * 0.2);
        // Snap to the circuit grid, clamp to the box, push clear of the
        // label.
        let x = Math.round((cx + Math.cos(angle) * spanX * reach) / GRID) * GRID;
        let y = Math.round((cy + Math.sin(angle) * spanY * reach) / GRID) * GRID;
        // A small breathing gap from the illustration's edges — the
        // biggest node (~6px half-size) still clears them.
        x = Math.min(this.w - 14, Math.max(14, x));
        y = Math.min(this.h - 14, Math.max(14, y));
        const k = Math.max(Math.abs(x - cx) / (rx + 22), Math.abs(y - cy) / (ry + 18));
        if (k < 1) {
          x = cx + (x - cx) / k;
          y = cy + (y - cy) / k;
        }
        nodes.push({
          x,
          y,
          // The route's shape: vertical-first or horizontal-first, and
          // which lane it leaves the box on.
          vFirst: rnd() < 0.5,
          lane: (Math.floor(rnd() * 3) - 1) * 12,
          delay: rnd() * RAY_STAGGER_S,
          ...look(rnd),
        });
      }
    }
    nodes.sort((a, b) => Math.atan2(a.y - cy, a.x - cx) - Math.atan2(b.y - cy, b.x - cx));
    return nodes;
  },

  // The entrance's resting cloud: uniform, calm dots hovering CLOSE to
  // the label (overlapping the box is fine) before they pull in and
  // shoot out.
  restNodes() {
    if (!this.rest) {
      const rnd = makeRng(31337);
      const { cx, cy, rx, ry } = this.hubGeometry();
      this.rest = [];
      for (let i = 0; i < NODE_COUNT; i++) {
        const angle = rnd() * Math.PI * 2;
        const dirX = Math.cos(angle);
        const dirY = Math.sin(angle);
        // Every dot clears the box (plus the wander's amplitude): scale
        // the direction to the expanded box border, then push outward —
        // the cloud rings the label, never sitting inside it.
        const minReach = 1 / Math.max(Math.abs(dirX) / (rx + 20), Math.abs(dirY) / (ry + 16));
        const reach = minReach + easeOut(rnd()) * 48;
        this.rest.push({
          x: cx + dirX * reach,
          y: cy + dirY * reach,
          r: 4 + rnd(),
          a: 0.45 + rnd() * 0.2,
          shade: Math.floor(rnd() * 3),
          shape: Math.floor(rnd() * 3),
          cached: false,
        });
      }
      this.rest.sort((a, b) => Math.atan2(a.y - cy, a.x - cx) - Math.atan2(b.y - cy, b.x - cx));
    }
    return this.rest;
  },

  buildGraph(seed) {
    const rnd = makeRng(seed);
    // Varied size, opacity, and purple shade give the cloud depth — some
    // dots recede, some sit forward — with a few random nodes in the
    // deepest purple: artifacts resolved from the cache.
    const nodes = this.placeNodes(rnd, () => ({
      r: 2.5 + rnd() * 3,
      a: 0.35 + rnd() * 0.65,
      shade: Math.floor(rnd() * 3),
      shape: Math.floor(rnd() * 3), // square | circle | diamond
      cached: rnd() < CACHED_CHANCE,
    }));

    // Interconnections: each module may link to its nearest not-yet-linked
    // neighbor, so the web stays sparse and never doubles up.
    const links = [];
    const linked = new Set();
    for (let i = 0; i < nodes.length; i++) {
      if (rnd() >= 0.55) continue;
      let best = -1;
      let bestDist = Infinity;
      for (let j = 0; j < nodes.length; j++) {
        if (j === i || linked.has(`${Math.min(i, j)}-${Math.max(i, j)}`)) continue;
        const dist = Math.hypot(nodes[i].x - nodes[j].x, nodes[i].y - nodes[j].y);
        if (dist > 34 && dist < 170 && dist < bestDist) {
          bestDist = dist;
          best = j;
        }
      }
      if (best < 0) continue;
      linked.add(`${Math.min(i, best)}-${Math.max(i, best)}`);
      links.push({ i, j: best, vFirst: rnd() < 0.5, delay: LINK_START_S + rnd() * LINK_STAGGER_S });
    }

    return { nodes, links };
  },

  // Where a node's route leaves the label box: a vertical-first route
  // exits the top/bottom face, a horizontal-first one the left/right
  // face, each offset onto the node's lane so routes share tracks like a
  // circuit board.
  rayAnchor(node, x, y) {
    const { cx, cy, rx, ry } = this.hubGeometry();
    if (node.vFirst) return [cx + node.lane, cy + (y >= cy ? ry : -ry)];
    return [cx + (x >= cx ? rx : -rx), cy + node.lane];
  },

  beginFrame() {
    const { ctx, w, h } = this;
    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = this.edgeColor;
    ctx.lineWidth = 1;
  },

  /* Orthogonal circuit route between two points: one sharp L bend,
     vertical-first or horizontal-first. p in 0..1 draws the leading
     fraction of the route. */
  drawRoute(rawX0, rawY0, rawX1, rawY1, vFirst, p) {
    const { ctx } = this;
    // Half-pixel snapping keeps the orthogonal legs as crisp 1px
    // hairlines instead of anti-aliased 2px smears.
    const x0 = Math.round(rawX0) + 0.5;
    const y0 = Math.round(rawY0) + 0.5;
    const x1 = Math.round(rawX1) + 0.5;
    const y1 = Math.round(rawY1) + 0.5;
    const bx = vFirst ? x0 : x1;
    const by = vFirst ? y1 : y0;
    const l1 = Math.hypot(bx - x0, by - y0);
    const l2 = Math.hypot(x1 - bx, y1 - by);
    const d = (l1 + l2) * p;
    ctx.moveTo(x0, y0);
    if (d <= l1 || l2 === 0) {
      const k = l1 ? d / l1 : 0;
      ctx.lineTo(x0 + (bx - x0) * k, y0 + (by - y0) * k);
      return;
    }
    if (l1 === 0) {
      const k = d / l2;
      ctx.lineTo(x0 + (x1 - x0) * k, y0 + (y1 - y0) * k);
      return;
    }
    const k = Math.min(1, (d - l1) / l2);
    ctx.lineTo(bx, by);
    ctx.lineTo(bx + (x1 - bx) * k, by + (y1 - by) * k);
  },

  drawRay(node, x, y, p) {
    const [x0, y0] = this.rayAnchor(node, x, y);
    this.drawRoute(x0, y0, x, y, node.vFirst, p);
  },

  drawDot(x, y, r, a, node) {
    const { ctx } = this;
    const trace = () => {
      ctx.beginPath();
      if (node.shape === 1) {
        ctx.arc(x, y, r, 0, Math.PI * 2);
      } else if (node.shape === 2) {
        const d = r * 1.3;
        ctx.moveTo(x, y - d);
        ctx.lineTo(x + d, y);
        ctx.lineTo(x, y + d);
        ctx.lineTo(x - d, y);
        ctx.closePath();
      } else {
        ctx.rect(x - r, y - r, r * 2, r * 2);
      }
    };
    // Punch the shape's footprint out of the line layer first, so routes
    // crossing beneath never show through the semi-transparent fill —
    // lines always sit below the shapes.
    ctx.globalCompositeOperation = "destination-out";
    trace();
    ctx.fill();
    ctx.globalCompositeOperation = "source-over";
    ctx.fillStyle = node.cached ? this.cachedColor : this.nodeShades[node.shade || 0];
    ctx.globalAlpha = a;
    trace();
    ctx.fill();
    ctx.globalAlpha = 1;
  },

  drawSteady(graph) {
    this.beginFrame();
    const { ctx } = this;
    ctx.beginPath();
    for (const node of graph.nodes) this.drawRay(node, node.x, node.y, 1);
    for (const link of graph.links) {
      const a = graph.nodes[link.i];
      const b = graph.nodes[link.j];
      this.drawRoute(a.x, a.y, b.x, b.y, link.vFirst, 1);
    }
    ctx.stroke();
    for (const node of graph.nodes) this.drawDot(node.x, node.y, node.r, node.a, node);
  },

  /* Lerp two node sets 1:1 — geometry interpolates, identity (shade,
     cached) flips at the halfway point so colors never smear. */
  lerpNodes(fromNodes, toNodes, mix) {
    return toNodes.map((node, i) => {
      const from = fromNodes[i] || node;
      const identity = mix < 0.5 ? from : node;
      return {
        x: from.x + (node.x - from.x) * mix,
        y: from.y + (node.y - from.y) * mix,
        r: from.r + (node.r - from.r) * mix,
        a: from.a + (node.a - from.a) * mix,
        shade: identity.shade,
        shape: identity.shape,
        cached: identity.cached,
      };
    });
  },

  /* Entrance (first cycle only): the cloud fades in and floats gently
     around the label, shoots out to the architecture, and the lines
     connect — rays first, interconnections after. */
  drawEntrance(graph, phase, t) {
    this.beginFrame();
    const { ctx } = this;
    const shoot = smoothstep(clamp01((phase - REST_HOLD_S) / SHOOT_S));
    const appear = easeOut(clamp01(phase / APPEAR_S));
    // The wander eases off as the shoot takes hold.
    const pos = this.lerpNodes(this.floatedRest(t, 1 - shoot), graph.nodes, shoot);

    const lineT = phase - (REST_HOLD_S + SHOOT_S + LINE_LAG_S);
    if (lineT > 0) {
      ctx.beginPath();
      for (let i = 0; i < graph.nodes.length; i++) {
        const p = easeOut(clamp01((lineT - graph.nodes[i].delay) / RAY_GROW_S));
        if (p > 0) this.drawRay(graph.nodes[i], pos[i].x, pos[i].y, p);
      }
      for (const link of graph.links) {
        const p = easeOut(clamp01((lineT - link.delay) / LINK_GROW_S));
        if (p <= 0) continue;
        const a = pos[link.i];
        const b = pos[link.j];
        this.drawRoute(a.x, a.y, b.x, b.y, link.vFirst, p);
      }
      ctx.stroke();
    }

    for (const p of pos) this.drawDot(p.x, p.y, p.r, p.a * appear, p);
  },

  /* The reform: the old system's links dissolve as its dots pull back
     into the floating cloud; the cloud hovers by the label while it
     retypes, then shoots out into the next architecture and its
     interconnections draw in. Rays stay attached throughout. */
  drawMorph(from, to, phase, t) {
    this.beginFrame();
    const { ctx } = this;
    const gather = smoothstep(clamp01(phase / GATHER_S));
    const shoot = smoothstep(clamp01((phase - GATHER_S - FLOAT_HOLD_S) / SHOOT_S));
    const rest = this.floatedRest(t, Math.min(gather, 1 - shoot));
    const pos = shoot > 0 ? this.lerpNodes(rest, to.nodes, shoot) : this.lerpNodes(from.nodes, rest, gather);

    // All lines — rays and old interconnections — dissolve as the dots
    // pull close: while the cloud floats, only the dots stay.
    const fadeOut = 1 - gather;
    if (fadeOut > 0) {
      ctx.globalAlpha = fadeOut;
      ctx.beginPath();
      for (let i = 0; i < pos.length; i++) this.drawRay(from.nodes[i], pos[i].x, pos[i].y, 1);
      for (const link of from.links) {
        const a = pos[link.i];
        const b = pos[link.j];
        this.drawRoute(a.x, a.y, b.x, b.y, link.vFirst, 1);
      }
      ctx.stroke();
      ctx.globalAlpha = 1;
    }

    // Once the swarm lands, the lines return like the entrance: rays
    // extend first, the interconnections draw in after.
    const lineT = phase - (GATHER_S + FLOAT_HOLD_S + SHOOT_S + LINE_LAG_S);
    if (lineT > 0) {
      ctx.beginPath();
      for (let i = 0; i < to.nodes.length; i++) {
        const p = easeOut(clamp01((lineT - to.nodes[i].delay) / RAY_GROW_S));
        if (p > 0) this.drawRay(to.nodes[i], pos[i].x, pos[i].y, p);
      }
      for (const link of to.links) {
        const p = easeOut(clamp01((lineT - link.delay) / LINK_GROW_S));
        if (p <= 0) continue;
        const a = pos[link.i];
        const b = pos[link.j];
        this.drawRoute(a.x, a.y, b.x, b.y, link.vFirst, p);
      }
      ctx.stroke();
    }

    for (const p of pos) this.drawDot(p.x, p.y, p.r, p.a, p);
  },
};
