import { onThemeChange } from "../lib/theme.js";
import { whenInView } from "../lib/in-view.js";

/*
 * Home hero wave: a live graph drawn as a stippled point cloud.
 *
 * A cloudy ribbon and thin strands of dots stream left to right like a live
 * series (a new point every half second, the live end easing toward it), with
 * a far and a near strand scrolling at their own speeds for parallax, over
 * solid vertical graph guides. The graph fades out around the hero copy so
 * the text stays legible, and a mouse pointer brightens the ribbon under it.
 *
 * Two WebGL2 passes: one texel per stipple cell computes the signal, then
 * every device pixel draws the jittered dots and the guides. Without
 * WebGL2 the canvas is removed and the hero stays a plain bordered box.
 *
 * Mount on the hero element; it must contain a <canvas data-part="wave"> and a
 * [data-part="copy"] block. Under prefers-reduced-motion the graph draws one
 * fully revealed static frame and repaints only on resize and theme change.
 */

const PATTERN = {
  pitch: 4, // stipple cell, CSS px: each cell holds at most one dot
  seed: 20.3,
  gain: 1.0,
  floor: 0.05,
  drift: 0.5,
  loop: 22,
  guideGap: 56, // CSS px between graph guides
  pad: 24, // graph inset from the hero border, CSS px
};

// Inks are custom properties on the hero (see home-hero.css) that point at
// Noora tokens; they are resolved at mount and on every theme change, so the
// light/dark values come from the tokens. The background is the hero's own.
const INK_PROPERTIES = {
  guide: "--home-hero-wave-guide",
  mid: "--home-hero-wave-mid",
  hi: "--home-hero-wave-ink",
  hi2: "--home-hero-wave-ink-2",
};

const GRAPH = { tick: 0.5, lerp: 0.08, head: -0.03, pxPerSec: 30, minWin: 16, maxWin: 40 };

const VS = `#version 300 es
void main(){ vec2 p = vec2(float((gl_VertexID<<1)&2), float(gl_VertexID&2)); gl_Position = vec4(p*2.0-1.0, 0.0, 1.0); }`;

const LIB = `
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx)*.1031); p3 += dot(p3, p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
  return mix(mix(hash12(i),hash12(i+vec2(1,0)),u.x), mix(hash12(i+vec2(0,1)),hash12(i+vec2(1,1)),u.x), u.y); }
float fbm(vec2 p){ float a=.5, s=0.; for(int i=0;i<3;i++){ s+=a*vnoise(p); p=p*2.03+vec2(17.1,9.2); a*=.5; } return s; }
// Soft radial mask around the copy: the graph dims to a faint 20% over the
// text (never fully cleared, so it reads as passing behind the copy rather
// than stopping at an invisible wall) and eases back to full well outside it. The distance is a superellipse (4-norm) fitted to the copy box
// plus a margin, so the corners of a wide text block stay clear while the
// falloff still reads as round rather than rectangular.
float copyMask(vec2 p, vec4 box, float s){
  vec2 c = .5*(box.xy + box.zw);
  vec2 h = .5*(box.zw - box.xy) + 48.0*s;
  vec2 q = abs(p - c)/max(h, vec2(1.0));
  q *= q;
  float d = sqrt(sqrt(dot(q, q)));
  return mix(.2, 1.0, smoothstep(.85, 1.8, d));
}
`;

// Pass 1, one texel per cell: the graph signal (r) and the subject mask (g).
const FS_FIELD = `#version 300 es
precision highp float;
uniform vec2 uCellPx; uniform vec2 uFrame; uniform float uS; uniform float uPadPx;
uniform float uSeed; uniform vec2 uCirc; uniform float uGain; uniform float uFloor;
uniform vec4 uCopy; uniform vec3 uCur;
uniform sampler2D uLine; uniform float uScroll;
out vec4 o;
${LIB}
void main(){
  vec2 c = gl_FragCoord.xy - .5;
  vec2 ctr = (c + .5)*uCellPx;
  // graph space: edge to edge horizontally, inset only at the top and bottom
  vec2 g0 = vec2(0.0, uPadPx), g1 = vec2(uFrame.x, uFrame.y - uPadPx);
  float x = (ctr.x - g0.x)/(g1.x - g0.x);
  float v = 1.0 - (ctr.y - g0.y)/(g1.y - g0.y);
  float asp = (g1.x - g0.x)/(g1.y - g0.y);
  // Band widths are authored against a 600px-tall graph; this keeps them the
  // same in pixels however tall the hero grows, instead of thickening with it.
  float hs = 600.0*uS/(g1.y - g0.y);

  // uLine, per cell column: r = subject offset, g = far echo, b = near echo,
  // a = subject present. uScroll streams everything attached to the data.
  vec4 lt = texelFetch(uLine, ivec2(int(c.x), 0), 0);
  float uD = x + uScroll;
  // The live ribbon is a cloud: a core whose width breathes along the line,
  // clumped by noise, inside a wider, sparse spray of stray dots.
  float tex = fbm(vec2(uD*asp*7.0, v*7.0) + uCirc + uSeed);
  float clump = fbm(vec2(uD*asp*16.0, v*16.0) - uCirc*.5 + uSeed + 2.0);
  float base = .2 + .28*x;
  // Lift the graph gently over the copy: on short heroes (laptops) the copy
  // takes more of the height and the ribbon would dive straight into it. Over
  // the copy's columns the graph's vertical range is scaled toward the space
  // above the copy, by at most 20% so the line keeps its natural shape, and
  // eases back to the full range past the copy.
  float vLim = 1.0 - (uCopy.w + 110.0*uS - g0.y)/(g1.y - g0.y);
  float xr = uCopy.z/uFrame.x;
  float over = 1.0 - smoothstep(xr - .1, xr + .35, x);
  float fit = mix(1.0, clamp(vLim/(base + .35), .8, 1.0), over);
  float cM = (base + lt.r)*fit;
  float wM = (.022 + .026*(.5 + .5*sin(uD*3.1 + .7))*(.6 + .8*fbm(vec2(uD*asp*1.5, 3.0) + uSeed)))*hs;
  float dM = v - cM;
  float rM = exp(-dM*dM/(wM*wM*(dM < 0.0 ? 2.4 : 1.0)));
  float spray = exp(-dM*dM/(wM*wM*10.0))*.24*(.4 + .6*clump);
  // thin strands of dots trailing below the cloud, like the reference
  float cS = cM + (.1 + .04*sin(uD*6.6 + 2.0))*fit;
  float rS = exp(-pow((v - cS)/(.008*hs), 2.0))*(.35 + .65*(.5 + .5*sin(uD*3.7 + .4)));
  float subject = (rM*(.2 + .85*tex)*(.75 + .5*clump) + rS*.8 + spray)*lt.a;
  float cF = (base - .2 + lt.g)*fit;
  float rF = exp(-pow((v - cF)/(.012*hs), 2.0))*(.25 + .6*fbm(vec2((x + uScroll*.5)*asp*5.0, v*5.0) + uCirc*.5 + uSeed + 7.0));
  float cN = (base + .32 + lt.b)*fit;
  float rN = exp(-pow((v - cN)/(.016*hs), 2.0))*(.2 + .6*fbm(vec2((x + uScroll*1.7)*asp*3.0, v*3.0) - uCirc*1.6 + uSeed + 3.0));
  float l = subject*1.1 + rF*.5 + rN*.45;
  l = l*uGain - uFloor;

  if(uCur.z > .001){
    vec2 dc = (ctr - uCur.xy)/(140.0*uS);
    l += uCur.z*.35*exp(-dot(dc, dc))*smoothstep(.04, .3, l);
  }
  l *= copyMask(ctr, uCopy, uS);
  l *= step(0.0, v)*step(v, 1.0);
  o = vec4(clamp(l, 0.0, 1.0), clamp(subject, 0.0, 1.0), 0.0, 1.0);
}`;

// Pass 2, every device pixel: a stippled point cloud plus the guides. Each
// cell holds one candidate dot at a jittered position; it appears when the
// cell's signal beats the dot's random threshold, so dot density follows the
// signal. Size and brightness vary per dot. A pixel checks its 3x3 cells, so
// dots can overlap cell edges.
const FS_DRAW = `#version 300 es
precision highp float;
uniform sampler2D uL; uniform ivec2 uGrid; uniform vec2 uCellPx; uniform float uS; uniform vec2 uFrame; uniform float uPadPx;
uniform float uGuideGap; uniform vec4 uCopy; uniform float uIntro;
uniform vec3 cBg; uniform vec3 cGuide; uniform vec3 cMid; uniform vec3 cHi; uniform vec3 cHi2;
out vec4 o;
${LIB}
void main(){
  vec2 fc = gl_FragCoord.xy;
  ivec2 c = ivec2(floor(fc/uCellPx));
  vec3 col = cBg;

  // guides: solid 1px verticals at a fixed gap, running the full height of
  // the box (border to border) and rising from the bottom on load; centred as
  // a group so the first and last sit the same distance from the left and
  // right edges, and faded by colour under the copy mask
  float gm = copyMask(fc, uCopy, uS);
  vec3 guide = mix(cBg, cGuide, gm);
  float gN = max(1.0, floor((uFrame.x - 2.0*uPadPx)/uGuideGap) + 1.0);
  float gx0 = floor(.5*(uFrame.x - (gN - 1.0)*uGuideGap) + .5);
  float gk = clamp(floor((fc.x - gx0)/uGuideGap + .5), 0.0, gN - 1.0);
  float gxp = gx0 + gk*uGuideGap;
  float reach = uFrame.y*clamp(uIntro*1.6, 0.0, 1.0);
  if(gm > .01 && fc.x >= gxp && fc.x < gxp + uS && fc.y <= reach) col = guide;

  float best = 0.0;
  vec3 ink = cBg;
  for(int j = -1; j <= 1; j++){
    for(int i = -1; i <= 1; i++){
      ivec2 n = c + ivec2(i, j);
      if(n.x < 0 || n.y < 0 || n.x >= uGrid.x || n.y >= uGrid.y) continue;
      vec4 sv = texelFetch(uL, n, 0);
      float l = sv.r;
      vec2 fn = vec2(n);
      float h0 = hash12(fn + 11.3);
      if(h0 >= l) continue;
      // dither-style dots: crisp squares snapped to the CSS pixel grid, in a
      // few fixed sizes (1-3px) and three brightness steps, at jittered spots
      vec2 pos = floor((fn + .12 + .76*vec2(hash12(fn + 3.7), hash12(fn + 7.1)))*uCellPx/uS)*uS;
      float hr = hash12(fn + 19.9);
      // entrance: each dot has its own start time and steps up from nothing,
      // so the cloud fills in particle by particle rather than sweeping
      float t0 = hash12(fn + 31.7)*.85;
      float grow = smoothstep(t0, t0 + .15, uIntro);
      float side = floor(clamp(1.0 + 1.4*hr*hr + 1.1*l, 1.0, 3.0)*grow + .5)*uS;
      if(side <= 0.0) continue;
      vec2 q = fc - pos;
      if(q.x < 0.0 || q.y < 0.0 || q.x >= side || q.y >= side) continue;
      float hb = hash12(fn + 23.1);
      float k = .5 + .25*floor(hb*2.999);
      if(k > best){
        best = k;
        float m = floor(smoothstep(.4, .95, l)*(.3 + .7*hb)*3.0 + .5)/3.0;
        ink = sv.g > .2 ? mix(cHi, cHi2, m) : cMid;
      }
    }
  }
  // the guides sit behind the graph: a dot replaces whatever is under it,
  // and its brightness steps blend toward the background, not the guide
  o = vec4(best > 0.0 ? mix(cBg, ink, best) : col, 1.0);
}`;

// Exact port of the GLSL hash12 in float32, so the series is deterministic.
const f32 = Math.fround;
const frc = (v) => v - Math.floor(v);
function hash12(x, y) {
  let px = f32(frc(f32(x * 0.1031)));
  let py = f32(frc(f32(y * 0.1031)));
  let pz = f32(frc(f32(x * 0.1031)));
  const d = f32(f32(px * f32(py + 33.33)) + f32(py * f32(pz + 33.33)) + f32(pz * f32(px + 33.33)));
  px = f32(px + d);
  py = f32(py + d);
  pz = f32(pz + d);
  return f32(frc(f32(f32(px + py) * pz)));
}
function vn1(x, seed) {
  const i = Math.floor(x);
  const f = x - i;
  const u = f * f * (3 - 2 * f);
  const a = hash12(i, seed) * 2 - 1;
  const b = hash12(i + 1, seed) * 2 - 1;
  return a + (b - a) * u;
}
const sv = (t, seed) => 0.15 * vn1(t / 11, seed) + 0.045 * vn1(t / 3.6, seed + 4.0);
const gValue = (k) => sv(k * GRAPH.tick, 3.1) + 0.01 * (hash12(k, 11.3) * 2 - 1);

// Resolve a computed CSS color (rgb(), oklch(), …) to RGB floats via a 1x1
// 2D canvas, which converts any color space it can parse to sRGB.
function cssColorToRgb(color, ctx) {
  ctx.clearRect(0, 0, 1, 1);
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 1, 1);
  const d = ctx.getImageData(0, 0, 1, 1).data;
  return [d[0] / 255, d[1] / 255, d[2] / 255];
}

export const HomeHeroWave = {
  mounted() {
    this.canvas = this.el.querySelector('canvas[data-part="wave"]');
    this.copy = this.el.querySelector('[data-part="copy"]');
    if (!this.canvas || !this.copy) return;

    const gl = this.canvas.getContext("webgl2", { antialias: false, alpha: false, preserveDrawingBuffer: false });
    if (!gl) {
      this.canvas.remove();
      return;
    }
    this.gl = gl;
    try {
      this.progs = { field: this.program(FS_FIELD), draw: this.program(FS_DRAW) };
    } catch (err) {
      console.error(err);
      this.canvas.remove();
      this.gl = null;
      return;
    }
    this.vao = gl.createVertexArray();

    this.reducedQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    this.reduced = this.reducedQuery.matches;
    this.S = 1;
    this.copyBox = [0, 0, 0, 0];
    this.tPhase = 0;
    this.intro = this.reduced ? 1 : 0;
    if (this.reduced) this.tPhase = 0.3;
    this.cur = { x: 0, y: 0, k: 0, target: 0 };
    this.g = { clock: 0, head: 0, hist: [], lastT: 0, lineTex: null, lineData: null };
    this.cells = null;
    this.raf = 0;
    this.cleanups = [];

    this.resolveInks();
    this.layout();

    // Resizing the canvas clears its drawing buffer, so repaint in the same
    // callback, before the browser paints, instead of waiting for the next
    // animation frame; otherwise a blank or stretched frame flashes.
    const ro = new ResizeObserver(() => {
      this.layout();
      this.render();
    });
    ro.observe(this.el);
    this.cleanups.push(() => ro.disconnect());
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(() => {
        if (!this.gl) return;
        this.layout();
        this.render();
      });
    }

    this.cleanups.push(
      onThemeChange(() => {
        this.resolveInks();
        this.render();
      }),
    );

    const onMove = (e) => {
      if (e.pointerType !== "mouse") return;
      const b = this.el.getBoundingClientRect();
      this.cur.x = e.clientX - b.left;
      this.cur.y = e.clientY - b.top;
      this.cur.target = 1;
    };
    const onLeave = () => {
      this.cur.target = 0;
    };
    this.el.addEventListener("pointermove", onMove);
    this.el.addEventListener("pointerleave", onLeave);
    this.cleanups.push(() => {
      this.el.removeEventListener("pointermove", onMove);
      this.el.removeEventListener("pointerleave", onLeave);
    });

    this.render();
    if (this.reduced) return;

    let last = performance.now();
    const loop = (now) => {
      this.raf = requestAnimationFrame(loop);
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      if (document.hidden) return;
      this.intro = Math.min(1, this.intro + dt / 2.2);
      this.tPhase = (this.tPhase + dt / PATTERN.loop) % 1;
      this.cur.k += (this.cur.target - this.cur.k) * Math.min(1, dt * 5);
      this.render();
    };
    this.cleanups.push(
      whenInView(this.el, {
        rootMargin: "0px",
        enter: () => {
          last = performance.now();
          this.g.lastT = 0;
          this.raf = requestAnimationFrame(loop);
        },
        leave: () => {
          cancelAnimationFrame(this.raf);
        },
      }),
    );
  },

  destroyed() {
    cancelAnimationFrame(this.raf);
    (this.cleanups || []).forEach((fn) => fn());
    const gl = this.gl;
    if (!gl) return;
    if (this.cells) {
      gl.deleteTexture(this.cells.t);
      gl.deleteFramebuffer(this.cells.f);
    }
    if (this.g.lineTex) gl.deleteTexture(this.g.lineTex);
    Object.values(this.progs).forEach((p) => gl.deleteProgram(p));
    gl.deleteVertexArray(this.vao);
    this.gl = null;
  },

  program(fs) {
    const gl = this.gl;
    const compile = (type, src) => {
      const s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    };
    const p = gl.createProgram();
    gl.attachShader(p, compile(gl.VERTEX_SHADER, VS));
    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fs));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    p.u = {};
    const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(p, i);
      p.u[info.name] = gl.getUniformLocation(p, info.name);
    }
    return p;
  },

  // Custom properties compute to their unresolved token text (light-dark()
  // included), so each one is applied as a probe's color and read back as the
  // browser's resolved color for the current scheme.
  resolveInks() {
    const c = document.createElement("canvas");
    c.width = c.height = 1;
    const ctx = c.getContext("2d", { willReadFrequently: true });
    const probe = document.createElement("span");
    probe.hidden = true;
    this.el.appendChild(probe);
    const ink = { bg: cssColorToRgb(getComputedStyle(this.el).backgroundColor, ctx) };
    for (const [key, property] of Object.entries(INK_PROPERTIES)) {
      probe.style.color = `var(${property})`;
      ink[key] = cssColorToRgb(getComputedStyle(probe).color, ctx);
    }
    probe.remove();
    this.ink = ink;
  },

  layout() {
    const b = this.el.getBoundingClientRect();
    const S = Math.max(1, Math.min(2, Math.round(window.devicePixelRatio || 1)));
    this.S = S;
    const W = Math.max(1, Math.round(b.width * S));
    const H = Math.max(1, Math.round(b.height * S));
    if (this.canvas.width !== W || this.canvas.height !== H) {
      this.canvas.width = W;
      this.canvas.height = H;
    }
    // The copy's ink bounds (text runs and buttons), in device px with a
    // bottom-left origin, so the graph can clear a soft gap around them.
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = -Infinity;
    let y1 = -Infinity;
    const add = (r) => {
      if (!r.width) return;
      x0 = Math.min(x0, r.left);
      y0 = Math.min(y0, r.top);
      x1 = Math.max(x1, r.right);
      y1 = Math.max(y1, r.bottom);
    };
    for (const el of this.copy.querySelectorAll("h1, p")) {
      const range = document.createRange();
      range.selectNodeContents(el);
      for (const r of range.getClientRects()) add(r);
    }
    for (const el of this.copy.querySelectorAll("a, button")) add(el.getBoundingClientRect());
    this.copyBox =
      x0 === Infinity ? [0, 0, 0, 0] : [(x0 - b.left) * S, (b.bottom - y1) * S, (x1 - b.left) * S, (b.bottom - y0) * S];
  },

  ensureCells(w, h) {
    const gl = this.gl;
    if (this.cells && this.cells.w === w && this.cells.h === h) return;
    if (this.cells) {
      gl.deleteTexture(this.cells.t);
      gl.deleteFramebuffer(this.cells.f);
    }
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    this.nearest();
    const f = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, f);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
    this.cells = { t, f, w, h };
  },

  nearest() {
    const gl = this.gl;
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  },

  seedGraph() {
    const g = this.g;
    const k0 = Math.floor(g.clock / GRAPH.tick);
    const n = Math.ceil(GRAPH.maxWin / GRAPH.tick) + 4;
    g.hist = [];
    for (let k = k0 - n; k <= k0; k++) g.hist.push({ t: k * GRAPH.tick, v: gValue(k) });
    g.head = gValue(k0);
  },

  // Streams the live series: a committed point every tick, the live end easing
  // toward the next value, history scrolling right. Fills one texel per cell
  // column for the field shader.
  stepGraph(Wc, cols) {
    const gl = this.gl;
    const g = this.g;
    const now = performance.now() / 1000;
    const dt = Math.min(0.05, g.lastT ? now - g.lastT : 0);
    g.lastT = now;
    if (!g.hist.length) this.seedGraph();
    if (!this.reduced) g.clock += dt;
    const kN = Math.floor(g.clock / GRAPH.tick);
    while (g.hist[g.hist.length - 1].t < kN * GRAPH.tick - 1e-6) {
      g.hist.push({ t: (Math.round(g.hist[g.hist.length - 1].t / GRAPH.tick) + 1) * GRAPH.tick, v: g.head });
    }
    g.head += (gValue(kN + 1) - g.head) * (1 - Math.pow(1 - GRAPH.lerp, dt * 60));
    while (g.hist.length > 4 && g.hist[2].t < g.clock - GRAPH.maxWin * 1.2) g.hist.shift();

    // graph x runs edge to edge, matching the field shader
    const gw = Wc;
    const win = Math.max(GRAPH.minWin, Math.min(GRAPH.maxWin, gw / GRAPH.pxPerSec));
    const head = GRAPH.head;
    const tAt = (x) => g.clock - (x - head) * win;
    // Catmull-Rom through the committed points plus the eased live end.
    const pts = g.hist.map((p) => [p.t, p.v]);
    pts.push([g.clock, g.head]);
    let j = 0;
    const sample = (t) => {
      while (j < pts.length - 2 && pts[j + 1][0] < t) j++;
      const p0 = pts[Math.max(0, j - 1)];
      const p1 = pts[j];
      const p2 = pts[j + 1];
      const p3 = pts[Math.min(pts.length - 1, j + 2)];
      const f = Math.min(1, Math.max(0, (t - p1[0]) / Math.max(1e-6, p2[0] - p1[0])));
      const f2 = f * f;
      const f3 = f2 * f;
      return (
        0.5 *
        (2 * p1[1] +
          (-p0[1] + p2[1]) * f +
          (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * f2 +
          (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * f3)
      );
    };
    if (!g.lineData || g.lineData.length !== cols * 4) g.lineData = new Float32Array(cols * 4);
    // Right to left, so data time only increases and sample() can walk forward.
    for (let i = cols - 1; i >= 0; i--) {
      const x = ((i + 0.5) * PATTERN.pitch) / gw;
      const on = x >= head;
      g.lineData[i * 4] = on ? sample(tAt(x)) : sample(g.clock);
      g.lineData[i * 4 + 1] = (0.1 / 0.15) * sv((x - (g.clock * 0.5) / win) * win, 7.7);
      g.lineData[i * 4 + 2] = (0.13 / 0.15) * sv((x - (g.clock * 1.7) / win) * win, 5.3);
      g.lineData[i * 4 + 3] = on ? 1 : 0;
    }
    if (!g.lineTex) {
      g.lineTex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, g.lineTex);
      this.nearest();
    }
    gl.bindTexture(gl.TEXTURE_2D, g.lineTex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, cols, 1, 0, gl.RGBA, gl.FLOAT, g.lineData);
    return -g.clock / win;
  },

  render() {
    const gl = this.gl;
    if (!gl) return;
    const S = this.S;
    const W = this.canvas.width;
    const H = this.canvas.height;
    const cw = PATTERN.pitch * S;
    const ch = cw;
    const pad = PATTERN.pad * S;
    const cols = Math.ceil(W / cw);
    const rows = Math.ceil(H / ch);
    this.ensureCells(cols, rows);
    const ink = this.ink;
    gl.bindVertexArray(this.vao);

    const scroll = this.stepGraph(W / S, cols);

    let p = this.progs.field;
    let u = p.u;
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.cells.f);
    gl.viewport(0, 0, cols, rows);
    gl.useProgram(p);
    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, this.g.lineTex);
    gl.uniform1i(u.uLine, 2);
    gl.activeTexture(gl.TEXTURE0);
    const ang = 2 * Math.PI * this.tPhase;
    gl.uniform2f(u.uCellPx, cw, ch);
    gl.uniform2f(u.uFrame, W, H);
    gl.uniform1f(u.uS, S);
    gl.uniform1f(u.uPadPx, pad);
    gl.uniform1f(u.uSeed, PATTERN.seed);
    gl.uniform2f(u.uCirc, Math.cos(ang) * PATTERN.drift, Math.sin(ang) * PATTERN.drift);
    gl.uniform1f(u.uGain, PATTERN.gain);
    gl.uniform1f(u.uFloor, PATTERN.floor);
    gl.uniform4f(u.uCopy, ...this.copyBox);
    gl.uniform3f(u.uCur, this.cur.x * S, (this.el.clientHeight - this.cur.y) * S, this.cur.k);
    gl.uniform1f(u.uScroll, scroll);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    p = this.progs.draw;
    u = p.u;
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, W, H);
    gl.useProgram(p);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.cells.t);
    gl.uniform1i(u.uL, 0);
    gl.uniform2i(u.uGrid, cols, rows);
    gl.uniform2f(u.uCellPx, cw, ch);
    gl.uniform1f(u.uS, S);
    gl.uniform2f(u.uFrame, W, H);
    gl.uniform1f(u.uPadPx, pad);
    gl.uniform1f(u.uGuideGap, PATTERN.guideGap * S);
    gl.uniform4f(u.uCopy, ...this.copyBox);
    gl.uniform1f(u.uIntro, this.intro);
    gl.uniform3f(u.cBg, ...ink.bg);
    gl.uniform3f(u.cGuide, ...ink.guide);
    gl.uniform3f(u.cMid, ...ink.mid);
    gl.uniform3f(u.cHi, ...ink.hi);
    gl.uniform3f(u.cHi2, ...ink.hi2);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  },
};
