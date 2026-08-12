/*
 * Bayer-ordered dither texture, colored from the marketing neutral tokens
 * (resolved from computed styles at mount, so retuning the ramp retunes the
 * texture).
 *
 * Two conceptual layers:
 *   1. Source signal — a vertical linear gradient (sparse top, dense
 *      bottom) optionally modulated by a slow drifting wave field. Plain
 *      grayscale; carries no texture of its own.
 *   2. Bayer dither — an ordered 8x8 threshold applied on top, turning the
 *      signal into the dot pattern.
 *
 * Rendered by a tiny WebGL fragment shader (one fullscreen triangle, no
 * textures — very cheap), with a canvas-2D fallback when WebGL is missing.
 * Mount on a <canvas> absolutely positioned inside the area to fill.
 *
 * Options (data attributes), all tunable from the template:
 *
 * Wave layer (the source signal):
 *   data-top:        signal density at the top edge, 0..1 (default 0)
 *   data-bottom:     signal density at the bottom edge, 0..1 (default 0.9)
 *   data-wave:       wave modulation amplitude, 0 = pure gradient (default 0.1)
 *   data-wave-scale: wave frequency multiplier (default 1)
 *   data-speed:      wave drift speed multiplier, 0 = static (default 1)
 *   data-phase:      clock offset in seconds, so canvases sharing a recipe
 *                    show different parts of the wave (default 0)
 *
 * Dither layer:
 *   data-dither:     "on" | "off" (default on). Off bypasses the Bayer
 *                    threshold and renders the raw signal as a pixelated
 *                    grayscale ramp — useful for tuning the wave layer.
 *   data-pitch:      pixel/cell size in CSS px (default 2)
 *   data-dot:        dot size inside the cell in CSS px (default = pitch)
 *   data-levels:     posterize the signal into N discrete steps before
 *                    rendering, 0 = continuous (default 0)
 *   data-opacity:    dot opacity, 0..1 (default 0.4)
 *   data-colors:     comma-separated CSS custom property names forming the
 *                    shallow→deep dot color ramp, 2–4 entries (default the
 *                    marketing neutral ramp)
 *   data-fade-px:    when set, the vertical density ramp runs from data-top
 *                    at the top edge down to data-bottom this many CSS px
 *                    below it, instead of spanning the full canvas height —
 *                    for canvases whose height changes but whose visible
 *                    band should not stretch
 *   data-noise:      0..1 per-cell random jitter blended into the Bayer
 *                    threshold; breaks the ordered pattern's straight-row
 *                    look toward a grainier stochastic dither (default 0)
 *   data-matrix:     "4" switches from the 8×8 Bayer matrix to a coarse
 *                    brick-dash tile — ramps render as scattered dashes,
 *                    offset brick rows, lines, then dense fill (default 8)
 *   data-mask:       selector for an SVG <path> — or an element containing
 *                    <path>s — whose filled, blurred silhouette multiplies
 *                    the density field, so the shape's edges dissolve into
 *                    dither instead of being clipped hard. Coords are in
 *                    host CSS px unless data-mask-viewbox is set.
 *   data-mask-viewbox: "W H" — the mask paths' coordinate space; the
 *                    silhouette is scaled from it to fill the canvas
 *   data-mask-blur:  mask edge softness in px (default 8)
 *   data-hover:      "off" disables the cursor-proximity glow (default on)
 */

import { onThemeChange } from "../lib/theme.js";

const BAYER8 = [
  0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54,
  22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29,
  53, 21,
];

// Brick-dash 8×4 tile — see bayer4 in the shader.
const BAYER4 = [
  1, 0, 2, 3, 17, 16, 18, 19, 21, 20, 22, 23, 5, 4, 6, 7, 9, 8, 10, 11, 25, 24, 26, 27, 29, 28, 30, 31, 13, 12, 14, 15,
];

const VERTEX_SRC = `
attribute vec2 a_position;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const FRAGMENT_SRC = `
/* highp where available: Chrome's ANGLE promotes mediump to FP32 anyway, but
   Firefox's backend can honor it as real FP16, whose ~3 decimal digits wreck
   the device-px coordinates, the growing u_time, and the sin-based cell hash
   — the field then jumps coarsely every tick and cells strobe across the
   Bayer threshold (constant flicker on Firefox). */
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform vec2 u_resolution;   /* device px */
uniform float u_time;
uniform float u_pitch;       /* device px per dither cell */
uniform float u_dot;         /* device px dot size inside the cell */
uniform float u_glow;        /* eased hover strength, 0..1 */
uniform float u_mouseX;      /* eased cursor x, 0..1 across the canvas */
uniform float u_top;         /* signal density at the top edge */
uniform float u_bottom;      /* signal density at the bottom edge */
uniform float u_waveAmp;     /* wave layer amplitude, 0 = pure gradient */
uniform float u_waveScale;   /* wave layer frequency multiplier */
uniform float u_levels;      /* signal quantization steps, 0 = continuous */
uniform float u_dither;      /* 1 = Bayer dither, 0 = raw signal */
uniform float u_opacity;     /* dot opacity, 0..1 */
uniform vec3 u_c0;           /* color ramp, shallow → deep */
uniform vec3 u_c1;
uniform vec3 u_c2;
uniform vec3 u_c3;
uniform float u_colorCount;  /* ramp entries in use, 2..4 */
uniform float u_fadePx;      /* fixed ramp length in device px, 0 = full height */
uniform float u_noise;       /* random threshold jitter, 0 = pure Bayer */
uniform float u_matrix4;     /* 1 = 4x4 Bayer matrix instead of 8x8 */
uniform sampler2D u_mask;    /* blurred shape silhouette, multiplies density */
uniform float u_hasMask;

/* Cheap per-cell hash for the stochastic jitter. */
float cellHash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

/* Classic 8x8 Bayer threshold, computed procedurally (no arrays/textures):
   the base 2x2 pattern on the finest bits is most significant, matching the
   standard matrix (and the pre-dithered Figma exports). */
float bayer8(vec2 cell) {
  vec2 p = floor(cell);
  float v = 0.0;
  float w = 16.0;
  for (int i = 0; i < 3; i++) {
    vec2 b = mod(p, 2.0);
    v += (2.0 * mod(b.x + b.y, 2.0) + b.y) * w;
    w /= 4.0;
    p = floor(p / 2.0);
  }
  return v / 64.0;
}

/* Coarse "brick-dash" variant (8×4 tile): each row splits into two 4-cell
   dash slots whose fill order alternates like brickwork, so ramps render as
   scattered dashes → offset brick dashes → lines → dense fill — the
   design's dither look, instead of the Bayer checker. */
float bayer4(vec2 cell) {
  float r = mod(floor(cell.y), 4.0);
  float xm = mod(floor(cell.x), 8.0);
  float side = step(4.0, xm);          /* 0 = left dash slot, 1 = right */
  float p = mod(xm, 4.0);
  float perm = p < 0.5 ? 1.0 : (p < 1.5 ? 0.0 : p); /* dash grows from inside */
  float base =
    r < 0.5 ? (side < 0.5 ? 0.0 : 16.0) :
    r < 1.5 ? (side < 0.5 ? 20.0 : 4.0) :
    r < 2.5 ? (side < 0.5 ? 8.0 : 24.0) :
              (side < 0.5 ? 28.0 : 12.0);
  return (base + perm) / 32.0;
}

float bayer(vec2 cell) {
  return u_matrix4 > 0.5 ? bayer4(cell) : bayer8(cell);
}

/* ── Layer 1: source signal ──
   Vertical linear gradient plus a slow, broad wave modulation. The waves
   only bend the gradient's iso-lines; with u_waveAmp = 0 the signal is the
   exact Figma ramp. */
float sourceField(vec2 uv, float t) {
  float g = mix(u_top, u_bottom, uv.y);
  float x = uv.x * u_waveScale;
  float w = 0.55 * sin(x * 5.1 - t * 0.5 + uv.y * 1.8)
          + 0.3 * sin(x * 9.3 + t * 0.35 + 1.7)
          + 0.15 * sin(uv.y * 6.7 * u_waveScale + t * 0.25);
  return g + u_waveAmp * w;
}

void main() {
  vec2 cell = floor(gl_FragCoord.xy / u_pitch);
  vec2 centerPx = (cell + 0.5) * u_pitch;
  /* uv with y pointing DOWN (v=1 at the bottom edge), like the design. */
  vec2 uv = vec2(centerPx.x / u_resolution.x, 1.0 - centerPx.y / u_resolution.y);
  /* Shape mask is sampled in canvas space, before any ramp remapping. */
  float maskA = u_hasMask > 0.5 ? texture2D(u_mask, uv).a : 1.0;
  if (maskA < 0.01) discard;

  /* Fixed-length ramp: compress the gradient into the first u_fadePx below
     the top edge instead of the full height. */
  if (u_fadePx > 0.5) {
    uv.y = clamp(uv.y * u_resolution.y / u_fadePx, 0.0, 1.0);
  }

  /* Optional dot inset (data-dot < data-pitch) for airier halftone looks;
     at the default (dot = pitch) cells tile fully like a real dithered
     image: past 50%, the tone fuses solid with background pinholes. */
  vec2 local = gl_FragCoord.xy - cell * u_pitch;
  float inset = (u_pitch - u_dot) * 0.5;
  if (local.x < inset || local.x > inset + u_dot || local.y < inset || local.y > inset + u_dot) {
    discard;
  }

  /* Hover: the signal gently brightens under the cursor — an eased bump
     centered on the cursor's x, fading with distance. */
  float proximity = exp(-pow((uv.x - u_mouseX) * 3.0, 2.0));
  float n = (sourceField(uv, u_time) + u_glow * 0.15 * proximity) * maskA;

  /* Optional posterization: snap the signal to discrete steps so the dither
     shows distinct pattern bands instead of a continuous ramp. */
  if (u_levels > 0.5) {
    n = floor(clamp(n, 0.0, 1.0) * u_levels + 0.5) / u_levels;
  }

  /* Cap < 1 keeps background pinholes alive in the densest zones. */
  n = clamp(n, 0.0, 0.95);
  float depth = smoothstep(0.35, 0.8, n);

  /* Map depth onto the ramp: the integer part picks the segment, the
     fraction dithers between its two shades. */
  float d = depth * (u_colorCount - 1.0);
  float base = min(floor(d), u_colorCount - 2.0);
  float frac = d - base;

  if (u_dither > 0.5) {
    /* ── Layer 2: ordered Bayer dither of the signal ──
       Dot color is dithered independently by depth along the ramp: shade 0
       in shallow areas, stepping deeper as the density grows. Premultiplied
       alpha. */
    float threshold =
      clamp(bayer(cell) + (cellHash(cell) - 0.5) * u_noise, 0.001, 0.999);
    if (threshold >= n) discard;
    vec2 shift = u_matrix4 > 0.5 ? vec2(2.0, 2.0) : vec2(4.0, 4.0);
    float shade = base + (bayer(cell + shift) < frac ? 1.0 : 0.0);
    vec3 color = shade < 0.5 ? u_c0 : shade < 1.5 ? u_c1 : shade < 2.5 ? u_c2 : u_c3;
    gl_FragColor = vec4(color * u_opacity, u_opacity);
  } else {
    /* Dither bypass: the raw signal as a pixelated ramp (cells still
       quantize to the pitch) — for tuning the wave layer directly. */
    vec3 a3 = base < 0.5 ? u_c0 : base < 1.5 ? u_c1 : u_c2;
    vec3 b3 = base < 0.5 ? u_c1 : base < 1.5 ? u_c2 : u_c3;
    vec3 color = mix(a3, b3, frac);
    float a = n * u_opacity;
    gl_FragColor = vec4(color * a, a);
  }
}
`;

function resolveTokenColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const resolved = getComputedStyle(probe).color;
  probe.remove();
  // Normalize any color syntax (rgb, oklch, ...) to RGBA via a 1x1 canvas.
  const c = document.createElement("canvas");
  c.width = c.height = 1;
  const ctx = c.getContext("2d");
  ctx.fillStyle = resolved;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return [r / 255, g / 255, b / 255];
}

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    console.error("[dither] shader compile failed:", gl.getShaderInfoLog(shader));
    return null;
  }
  return shader;
}

function numberOption(dataset, key, fallback) {
  const value = Number(dataset[key]);
  return Number.isFinite(value) ? value : fallback;
}

export const DitherTexture = {
  mounted() {
    this.canvas = this.el;
    this.raf = null;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const data = this.el.dataset;
    this.pitch = numberOption(data, "pitch", 2);
    this.dot = numberOption(data, "dot", this.pitch);
    this.top = numberOption(data, "top", 0);
    this.bottom = numberOption(data, "bottom", 0.9);
    this.waveAmp = numberOption(data, "wave", 0.1);
    this.waveScale = numberOption(data, "waveScale", 1);
    this.levels = numberOption(data, "levels", 0);
    this.speed = numberOption(data, "speed", 1);
    this.phase = numberOption(data, "phase", 0);
    this.dither = !["off", "false", "0"].includes(data.dither);
    this.opacity = numberOption(data, "opacity", 0.4);
    this.fadePx = numberOption(data, "fadePx", 0);
    this.noise = numberOption(data, "noise", 0);
    this.matrix4 = data.matrix === "4";
    const maskRoot = data.mask ? document.querySelector(data.mask) : null;
    this.maskPathEls = maskRoot
      ? maskRoot.tagName.toLowerCase() === "path"
        ? [maskRoot]
        : Array.from(maskRoot.querySelectorAll("path"))
      : [];
    const maskViewBox = (data.maskViewbox || "")
      .trim()
      .split(/[\s,]+/)
      .map(Number);
    this.maskViewBox =
      maskViewBox.length === 2 && maskViewBox.every((n) => Number.isFinite(n) && n > 0) ? maskViewBox : null;
    this.maskBlur = numberOption(data, "maskBlur", 8);
    this.maskAlpha = null;
    this.maskCanvas = null;
    // Hover strength and cursor-x ease per tick, brightening the signal.
    this.hovered = false;
    this.glowStrength = 0;
    this.pointerX = 0.5;
    this.easedX = 0.5;
    this.cleanups = [];

    const host = this.canvas.parentElement;
    this.rampTokens = (data.colors || "--marketing-illustration-neutral-3,--marketing-illustration-neutral-4")
      .split(",")
      .map((token) => token.trim())
      .filter(Boolean)
      .slice(0, 4);
    this.resolveRamp = () => {
      this.ramp = this.rampTokens.map((token) => resolveTokenColor(host, token));
      while (this.ramp.length < 2) this.ramp.push(this.ramp[0] || [0, 0, 0]);
    };
    this.resolveRamp();
    this.cleanups.push(
      onThemeChange(() => {
        this.resolveRamp();
        if (this.mode === "gl") this.uploadRamp();
        this.render(performance.now());
      }),
    );

    if (data.hover !== "off") {
      const onMove = (e) => {
        const rect = this.canvas.getBoundingClientRect();
        this.pointerX = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
        // Fresh entry: anchor the bump at the entry point so it grows in
        // place instead of sliding over from where it last was.
        if (!this.hovered && this.glowStrength < 0.02) this.easedX = this.pointerX;
        this.hovered = true;
      };
      const onLeave = () => (this.hovered = false);
      host.addEventListener("mousemove", onMove);
      host.addEventListener("mouseleave", onLeave);
      this.cleanups.push(() => {
        host.removeEventListener("mousemove", onMove);
        host.removeEventListener("mouseleave", onLeave);
      });
    }

    const gl = this.canvas.getContext("webgl", {
      alpha: true,
      antialias: false,
      depth: false,
      stencil: false,
      powerPreference: "low-power",
      // The loop draws on quantized 16Hz ticks and skips the rAF frames in
      // between. With the default (false) the buffer is invalidated after
      // each composite, and Firefox can composite that cleared buffer on
      // scroll/invalidation frames between draws — streaks and flicker.
      // Chrome re-composites from its retained texture either way.
      preserveDrawingBuffer: true,
    });
    if (gl && this.setupGL(gl)) {
      this.mode = "gl";
    } else {
      this.mode = "2d";
      this.ctx2d = this.canvas.getContext("2d");
    }

    this.resize = () => {
      const rect = host.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.dpr = dpr;
      this.width = Math.max(1, Math.round(rect.width));
      this.height = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.width * dpr;
      this.canvas.height = this.height * dpr;
      if (this.mode === "gl") this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      if (this.mode === "2d") this.ctx2d.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.buildMask();
      this.render(performance.now());
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(host);
    this.resize();

    // devicePixelRatio can change without the element changing size — the
    // window moving to a display with a different scale factor, or browser
    // zoom. The ResizeObserver above never fires for those, so the canvas keeps
    // a backing store sized for the old ratio and the browser scales it up:
    // coarse, blurry dots instead of crisp ones. Watch the ratio itself, and
    // re-arm after each change because a resolution query is pinned to the
    // value it was created with.
    const watchDpr = () => {
      const dpr = window.devicePixelRatio || 1;
      const query = window.matchMedia(`(resolution: ${dpr}dppx), (-webkit-device-pixel-ratio: ${dpr})`);
      const onChange = () => {
        this.resize();
        watchDpr();
      };
      query.addEventListener("change", onChange, { once: true });
      this.dprQuery = { query, onChange };
    };
    watchDpr();
    this.cleanups.push(() => {
      if (this.dprQuery) this.dprQuery.query.removeEventListener("change", this.dprQuery.onChange);
    });

    if (!this.reduced) {
      // Quantized clock: the field only advances on discrete ticks, so the
      // animation steps frame-by-frame like pixel art instead of gliding. The
      // rate is a balance — the wave's travel per tick is speed / TICK_HZ, so
      // too low and the drift reads as lag rather than as cadence.
      const TICK_HZ = 16;
      this.lastTick = -1;
      const tick = (now) => {
        this.raf = requestAnimationFrame(tick);
        // Skip work while hidden (e.g. the dropdown is closed).
        if (this.canvas.checkVisibility && !this.canvas.checkVisibility()) return;
        const step = Math.floor((now / 1000) * TICK_HZ);
        if (step === this.lastTick) return;
        this.lastTick = step;
        // Hover glow eases per tick (~5 ticks to settle). The factor is tuned
        // against TICK_HZ so the glow keeps its ~300ms feel: raise it if the
        // tick rate drops, lower it if the rate goes up.
        const target = this.hovered ? 1 : 0;
        this.glowStrength += (target - this.glowStrength) * 0.3;
        this.easedX += (this.pointerX - this.easedX) * 0.3;
        this.render((step / TICK_HZ) * 1000);
      };
      this.raf = requestAnimationFrame(tick);
    }
  },

  destroyed() {
    if (this.raf !== null) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
    this.cleanups.forEach((fn) => fn());
    // Browsers cap how many WebGL contexts a page may hold and don't reclaim
    // them promptly when a canvas goes away. Live navigation across pages with
    // several dither canvases can exhaust that pool, and a canvas that gets no
    // context silently falls back to the 2D path, so hand it back explicitly.
    if (this.mode === "gl" && this.gl) {
      const lose = this.gl.getExtension("WEBGL_lose_context");
      if (lose) lose.loseContext();
    }
  },

  setupGL(gl) {
    const vert = compile(gl, gl.VERTEX_SHADER, VERTEX_SRC);
    const frag = compile(gl, gl.FRAGMENT_SHADER, FRAGMENT_SRC);
    if (!vert || !frag) return false;
    const program = gl.createProgram();
    gl.attachShader(program, vert);
    gl.attachShader(program, frag);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      console.error("[dither] program link failed:", gl.getProgramInfoLog(program));
      return false;
    }
    gl.useProgram(program);

    // One fullscreen triangle.
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

    this.gl = gl;
    this.uniforms = {
      resolution: gl.getUniformLocation(program, "u_resolution"),
      time: gl.getUniformLocation(program, "u_time"),
      pitch: gl.getUniformLocation(program, "u_pitch"),
      dot: gl.getUniformLocation(program, "u_dot"),
      glow: gl.getUniformLocation(program, "u_glow"),
      mouseX: gl.getUniformLocation(program, "u_mouseX"),
      top: gl.getUniformLocation(program, "u_top"),
      bottom: gl.getUniformLocation(program, "u_bottom"),
      waveAmp: gl.getUniformLocation(program, "u_waveAmp"),
      waveScale: gl.getUniformLocation(program, "u_waveScale"),
      levels: gl.getUniformLocation(program, "u_levels"),
      dither: gl.getUniformLocation(program, "u_dither"),
      opacity: gl.getUniformLocation(program, "u_opacity"),
      c0: gl.getUniformLocation(program, "u_c0"),
      c1: gl.getUniformLocation(program, "u_c1"),
      c2: gl.getUniformLocation(program, "u_c2"),
      c3: gl.getUniformLocation(program, "u_c3"),
      colorCount: gl.getUniformLocation(program, "u_colorCount"),
      fadePx: gl.getUniformLocation(program, "u_fadePx"),
      noise: gl.getUniformLocation(program, "u_noise"),
      matrix4: gl.getUniformLocation(program, "u_matrix4"),
      mask: gl.getUniformLocation(program, "u_mask"),
      hasMask: gl.getUniformLocation(program, "u_hasMask"),
    };
    gl.uniform1i(this.uniforms.mask, 0);
    if (this.maskCanvas) this.uploadMask();
    this.uploadRamp();
    return true;
  },

  uploadRamp() {
    const { gl, uniforms } = this;
    const last = this.ramp[this.ramp.length - 1];
    gl.uniform3fv(uniforms.c0, this.ramp[0]);
    gl.uniform3fv(uniforms.c1, this.ramp[1] || last);
    gl.uniform3fv(uniforms.c2, this.ramp[2] || last);
    gl.uniform3fv(uniforms.c3, this.ramp[3] || last);
    gl.uniform1f(uniforms.colorCount, this.ramp.length);
  },

  // Rasterize the mask paths (host CSS px, or scaled from data-mask-viewbox),
  // blur them, and keep both an alpha buffer (2D fallback) and a GL texture
  // (shader) of the result.
  buildMask() {
    if (!this.maskPathEls.length || !this.width || !this.height) return;
    const sharp = document.createElement("canvas");
    sharp.width = this.width;
    sharp.height = this.height;
    const sctx = sharp.getContext("2d");
    if (this.maskViewBox) {
      sctx.scale(this.width / this.maskViewBox[0], this.height / this.maskViewBox[1]);
    }
    sctx.fillStyle = "#fff";
    for (const el of this.maskPathEls) {
      const d = el.getAttribute("d");
      if (d) sctx.fill(new Path2D(d));
    }
    const blurred = document.createElement("canvas");
    blurred.width = this.width;
    blurred.height = this.height;
    const bctx = blurred.getContext("2d");
    bctx.filter = `blur(${this.maskBlur}px)`;
    bctx.drawImage(sharp, 0, 0);
    this.maskCanvas = blurred;
    this.maskAlpha = bctx.getImageData(0, 0, this.width, this.height).data;
    if (this.mode === "gl") this.uploadMask();
  },

  uploadMask() {
    const gl = this.gl;
    if (!gl || !this.maskCanvas) return;
    if (!this.maskTexture) this.maskTexture = gl.createTexture();
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.maskTexture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, this.maskCanvas);
  },

  render(now) {
    const t = (now / 1000 + this.phase) * 0.35 * this.speed;
    if (this.mode === "gl") {
      const { gl, uniforms, dpr } = this;
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.uniform2f(uniforms.resolution, this.canvas.width, this.canvas.height);
      gl.uniform1f(uniforms.time, t);
      gl.uniform1f(uniforms.pitch, this.pitch * dpr);
      gl.uniform1f(uniforms.dot, this.dot * dpr);
      gl.uniform1f(uniforms.glow, this.glowStrength);
      gl.uniform1f(uniforms.mouseX, this.easedX);
      gl.uniform1f(uniforms.top, this.top);
      gl.uniform1f(uniforms.bottom, this.bottom);
      gl.uniform1f(uniforms.waveAmp, this.waveAmp);
      gl.uniform1f(uniforms.waveScale, this.waveScale);
      gl.uniform1f(uniforms.levels, this.levels);
      gl.uniform1f(uniforms.dither, this.dither ? 1 : 0);
      gl.uniform1f(uniforms.opacity, this.opacity);
      gl.uniform1f(uniforms.fadePx, this.fadePx * dpr);
      gl.uniform1f(uniforms.noise, this.noise);
      gl.uniform1f(uniforms.matrix4, this.matrix4 ? 1 : 0);
      gl.uniform1f(uniforms.hasMask, this.maskCanvas ? 1 : 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      return;
    }
    this.draw2d(t);
  },

  // Canvas-2D fallback (static-ish, no mouse glow) for WebGL-less browsers.
  draw2d(t) {
    const ctx = this.ctx2d;
    const { width, height, ramp, pitch } = this;
    const cols = Math.ceil(width / pitch);
    const rows = Math.ceil(height / pitch);
    ctx.clearRect(0, 0, width, height);
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        const u = x / cols;
        let v = y / rows;
        if (this.fadePx > 0) v = Math.min(1, (y * pitch + pitch / 2) / this.fadePx);
        // Layer 1: source signal, mirroring the shader.
        const wave =
          0.55 * Math.sin(u * this.waveScale * 5.1 - t * 0.5 + v * 1.8) +
          0.3 * Math.sin(u * this.waveScale * 9.3 + t * 0.35 + 1.7) +
          0.15 * Math.sin(v * 6.7 * this.waveScale + t * 0.25);
        let n = this.top + (this.bottom - this.top) * v + this.waveAmp * wave;
        if (this.maskAlpha) {
          const mx = Math.min(width - 1, Math.round(x * pitch + pitch / 2));
          const my = Math.min(height - 1, Math.round(y * pitch + pitch / 2));
          const m = this.maskAlpha[(my * width + mx) * 4 + 3] / 255;
          if (m < 0.01) continue;
          n *= m;
        }
        if (this.levels > 0.5) {
          n = Math.round(Math.min(Math.max(n, 0), 1) * this.levels) / this.levels;
        }
        // Layer 2: ordered Bayer dither + depth-dithered color, or the raw
        // pixelated signal when dithering is toggled off.
        n = Math.min(Math.max(n, 0), 0.95);
        const depth = Math.min(1, Math.max(0, (n - 0.35) / 0.45));
        // Depth → ramp segment + dithered fraction, mirroring the shader.
        const d = depth * (ramp.length - 1);
        const base = Math.min(Math.floor(d), ramp.length - 2);
        const frac = d - base;
        let rgb;
        if (this.dither) {
          let bayer = this.matrix4 ? BAYER4[(y & 3) * 8 + (x & 7)] / 32 : BAYER8[(y & 7) * 8 + (x & 7)] / 64;
          if (this.noise > 0) {
            const h = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
            bayer = Math.min(0.999, Math.max(0.001, bayer + (h - Math.floor(h) - 0.5) * this.noise));
          }
          if (bayer >= n) continue;
          const bayerShifted = this.matrix4
            ? BAYER4[((y + 2) & 3) * 8 + ((x + 2) & 7)] / 32
            : BAYER8[((y + 4) & 7) * 8 + ((x + 4) & 7)] / 64;
          rgb = ramp[base + (bayerShifted < frac ? 1 : 0)];
          ctx.globalAlpha = this.opacity;
        } else {
          const a = ramp[base];
          const b = ramp[base + 1];
          rgb = [a[0] + (b[0] - a[0]) * frac, a[1] + (b[1] - a[1]) * frac, a[2] + (b[2] - a[2]) * frac];
          ctx.globalAlpha = n * this.opacity;
        }
        ctx.fillStyle = `rgb(${rgb[0] * 255}, ${rgb[1] * 255}, ${rgb[2] * 255})`;
        const inset = (pitch - this.dot) / 2;
        ctx.fillRect(x * pitch + inset, y * pitch + inset, this.dot, this.dot);
      }
    }
  },
};
