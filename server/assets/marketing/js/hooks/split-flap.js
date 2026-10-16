// Split-flap counter for the cache globe page: a row of 90×128 tiles drawn
// in WebGL, pixel for pixel from the Figma "Split-flap" export (Split-flap.svg),
// with the classic flip between digits.
//
// Everything is authored in the SVG's design space (a tile is 90×128 units)
// and scaled to whatever size the host canvas gets from CSS, so the geometry
// below reads exactly like the SVG:
//
//   body        rounded rect 0,0 90×128 r8, black
//   hinge band  rect 4,53 82×22, #121212 (peeks through the 2px seam)
//   top flap    rounded-top rect 2,2 → 88,63 (r6) minus the two notches beside
//               the tab (x < 9.77 and x > 80.23 below y 53.69); vertical
//               gradient #121212 → #1E1E1E; a 2px inner shadow along its
//               bottom edges (black 25%); two 1px strokes inset by 0.5
//               (#747474 → #332233@13%, and black 0 → 30%); the digit in
//               #E7E7E7 clipped to the half; a 1px inner shadow along the
//               bottom edges over the lot (black 12%)
//   bottom flap the mirror of the top flap (65…126, tab 65…74.31); gradient
//               #121212 at the bottom → #1E1E1E at the hinge; a 2px inner
//               shadow along its bottom edges (black 25%); strokes
//               #2E2E2E@0 → #232323, and white 0 → 5%; the digit shifted up
//               1 unit; a 1px inner shadow along its top edges over the lot
//               (white 5%)
//   pins        rects 2,57 and 83,57, 5×15, gradient #121212 · #B1B1B1@33%
//               · #343434@55% · #020202
//
// The digit is Geist Mono at 105 units, centred on x=45.5 with its baseline
// on y=105, rendered once per resolution into a glyph atlas (2D canvas) and
// sampled by the shader.
//
// The flip: when a tile's digit changes, the new digit is drawn on the
// static top half and the old digit stays on the static bottom half, and
// one card falls between them. The card is simulated as a rigid body on the
// hinge: released with a kick, pulled round by gravity so it gains speed
// through the half turn (its front face shows the old top half, its back
// face the new bottom half), and on hitting the stack it bounces like a
// dropped ball — each bounce smaller and quicker than the last — before
// settling. Rotation happens in the vertex shader with a
// little perspective, and the card dims as it turns away from the light.
// Tiles that change together ripple left to right. A tile always steps
// through the digits one flap at a time, as the drum of a real board does:
// the intermediate flaps are driven fast and stop dead, only the flap that
// reaches the target bounces. On load the row starts at zeros and runs up
// to the current number the same way. Under prefers-reduced-motion digits
// change in place.
//
// The hook reads its digits from data-value and follows "split-flap:value"
// events (dispatched by the CacheGlobe hook, since this canvas lives inside
// a phx-update="ignore" block); the count of tiles is the length of the
// value.

const TILE_W = 90;
const TILE_H = 128;
const GAP = 8;
const HINGE = 64;
const GLYPH_FONT = 105;
// The flip is a small rigid-body simulation of one card on the hinge: the
// card starts standing in the top position, gets the motor's release kick
// (OMEGA), and gravity (GRAVITY, angular acceleration at 90°) carries it
// through the half turn; DRAG is air resistance. Past vertical the drum
// also presses the card onto the stack with a constant PRESS, so near the
// stack it behaves like a dropped ball rather than a pendulum: each bounce
// is RESTITUTION of the last in speed, so the bounces shrink and shorten
// geometrically (about 14°, 7°, 3°, 1.6°, 0.8° … with the gaps shrinking
// from 230ms to under 50ms) and the card is at rest about 0.85s after
// landing. REBOUND caps the first bounce so a fast fall
// never throws the card back up too far, and REST is the speed below which
// it stays down. A run-up flap is driven hard and stops dead, since the
// next card is already on its way.
const OMEGA = 6;
const GRAVITY = 70;
const DRAG = 1.2;
const PRESS = 22;
const RESTITUTION = 0.72;
const REBOUND = 4.0;
const REST = 0.15;
// Seen head-on, a lifted flap barely changes shape, so the bounce is sold
// by light: perspective leans the card toward the viewer (FOCAL, in tile
// heights), the lifted card brightens as it catches the light (GLINT), and
// it throws a shadow on the stack beneath (SHADE).
const FOCAL = 3;
const GLINT = 0.35;
const SHADE = 0.8;
const QUICK_OMEGA = 20;
const QUICK_GRAVITY = 300;
const STAGGER_MS = 45;
const MAX_STEP = 1 / 30;
const SUBSTEPS = 4;

const VERTEX = `
attribute vec2 a_pos;
uniform vec2 u_resolution;
uniform vec4 u_quad;
uniform float u_angle;
uniform float u_hinge;
uniform float u_focal;
varying vec2 v_pos;
void main() {
  vec2 px = u_quad.xy + a_pos * u_quad.zw;
  // Rotate the quad about the hinge line, then project with the eye on the
  // tile's centre so the moving flap leans toward the viewer.
  float dy = px.y - u_hinge;
  float y = u_hinge + dy * cos(u_angle);
  float z = dy * sin(u_angle);
  float w = 1.0 + z / u_focal;
  vec2 centre = vec2(u_quad.x + u_quad.z * 0.5, u_hinge);
  vec2 proj = centre + (vec2(px.x, y) - centre) / w;
  vec2 clip = (proj / u_resolution) * 2.0 - 1.0;
  gl_Position = vec4(clip.x * w, -clip.y * w, 0.0, w);
  v_pos = a_pos;
}
`;

const FRAGMENT = `
precision highp float;
uniform vec4 u_quad;
uniform vec2 u_tile;
uniform float u_scale;
uniform int u_layer;
uniform sampler2D u_glyphs;
uniform float u_glyph;
uniform float u_dim;
varying vec2 v_pos;

float sdBox(vec2 p, vec2 c, vec2 h) {
  vec2 d = abs(p - c) - h;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Rounded box with per-corner radii: r = (top-left, top-right, bottom-right,
// bottom-left), y pointing down.
float sdRBox(vec2 p, vec2 c, vec2 h, vec4 r) {
  vec2 q = p - c;
  float rad = q.x > 0.0 ? (q.y > 0.0 ? r.z : r.y) : (q.y > 0.0 ? r.w : r.x);
  vec2 d = abs(q) - h + rad;
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rad;
}

// Analytic coverage of a distance, one device pixel of anti-aliasing.
float cov(float d) {
  return clamp(0.5 - d * u_scale, 0.0, 1.0);
}

// The top flap outline in tile units: the rounded-top body (2,2 → 88,63)
// with a notch cut out of each bottom corner beside the tab. Subtracting the
// notches keeps the distance field exact inside the shape — a union of body
// and tab would leave a false edge along y=53.69 where the two coincide.
float sdFlap(vec2 p) {
  float body = sdRBox(p, vec2(45.0, 32.5), vec2(43.0, 30.5), vec4(6.0, 6.0, 0.0, 0.0));
  float left = sdBox(p, vec2(-0.11445, 126.847), vec2(9.88555, 73.152));
  float right = sdBox(p, vec2(90.11445, 126.847), vec2(9.88555, 73.152));
  return max(body, -min(left, right));
}

// Source-over in premultiplied alpha: c accumulates premultiplied colour.
vec4 over(vec4 dst, vec3 rgb, float a) {
  return vec4(rgb * a, a) + dst * (1.0 - a);
}

vec3 hex(float r, float g, float b) {
  return vec3(r, g, b) / 255.0;
}

void main() {
  vec2 p = (u_quad.xy + v_pos * u_quad.zw - u_tile) / u_scale;
  vec4 c = vec4(0.0);

  if (u_layer == 0) {
    float body = cov(sdRBox(p, vec2(45.0, 64.0), vec2(45.0, 64.0), vec4(8.0)));
    c = over(c, vec3(0.0), body);
    float band = cov(sdBox(p, vec2(45.0, 64.0), vec2(41.0, 11.0)));
    c = over(c, hex(18.0, 18.0, 18.0), band);
  } else if (u_layer == 1 || u_layer == 2) {
    bool bottom = u_layer == 2;
    // The bottom flap is the top flap mirrored about the hinge.
    vec2 q = bottom ? vec2(p.x, 128.0 - p.y) : p;
    float d = sdFlap(q);
    float inside = cov(d);
    if (inside <= 0.0) {
      gl_FragColor = vec4(0.0);
      return;
    }
    float t = clamp((q.y - 2.0) / 61.0, 0.0, 1.0);

    // Fill: #121212 at the far edge → #1E1E1E at the hinge.
    c = over(c, mix(hex(18.0, 18.0, 18.0), hex(30.0, 30.0, 30.0), t), inside);

    // Fill-level inner shadow (dy -2, black 25%): the 2 units inside every
    // edge that faces the hinge on the top flap, and the far edge on the
    // bottom flap (its filter offsets the other way once mirrored).
    float shadowDir = bottom ? -2.0 : 2.0;
    float shadow2 = inside * (1.0 - cov(sdFlap(q + vec2(0.0, shadowDir))));
    c = over(c, vec3(0.0), 0.25 * shadow2);

    // The two 1px strokes, inset by 0.5: the band between d = -1 and d = 0.
    float stroke = inside - cov(d + 1.0);
    if (bottom) {
      c = over(c, mix(hex(46.0, 46.0, 46.0), hex(35.0, 35.0, 35.0), t), stroke * t);
      c = over(c, vec3(1.0), stroke * 0.05 * t);
    } else {
      c = over(c, mix(hex(116.0, 116.0, 116.0), hex(51.0, 34.0, 51.0), t), stroke * mix(1.0, 0.1333, t));
      c = over(c, vec3(0.0), stroke * 0.3 * t);
    }

    // The digit, clipped to this half. The bottom half's glyph sits one unit
    // higher than the top half's in the source, so sample one unit lower.
    float gy = p.y + (bottom ? 1.0 : 0.0);
    float clip = bottom ? step(65.0, p.y) * step(p.y, 126.0) : step(2.0, p.y) * step(p.y, 63.0);
    clip *= step(2.0, p.x) * step(p.x, 88.0);
    vec2 uv = vec2((u_glyph * 90.0 + p.x) / 900.0, gy / 128.0);
    float g = texture2D(u_glyphs, uv).a * clip;
    c = over(c, hex(231.0, 231.0, 231.0), g);

    // Group-level inner shadow over everything: 1 unit along the hinge-side
    // edges — black 12% on the top flap, white 5% on the bottom flap.
    float shadow1 = inside * (1.0 - cov(sdFlap(q + vec2(0.0, 1.0))));
    if (bottom) {
      c = over(c, vec3(1.0), 0.05 * shadow1);
    } else {
      c = over(c, vec3(0.0), 0.12 * shadow1);
    }
  } else {
    float left = cov(sdBox(p, vec2(4.5, 64.5), vec2(2.5, 7.5)));
    float right = cov(sdBox(p, vec2(85.5, 64.5), vec2(2.5, 7.5)));
    float pin = max(left, right);
    float t = clamp((p.y - 57.0) / 15.0, 0.0, 1.0);
    vec3 g0 = hex(18.0, 18.0, 18.0);
    vec3 g1 = hex(177.0, 177.0, 177.0);
    vec3 g2 = hex(52.0, 52.0, 52.0);
    vec3 g3 = hex(2.0, 2.0, 2.0);
    vec3 grad = t < 0.327404
      ? mix(g0, g1, t / 0.327404)
      : (t < 0.548077 ? mix(g1, g2, (t - 0.327404) / 0.220673) : mix(g2, g3, (t - 0.548077) / 0.451923));
    c = over(c, grad, pin);
  }

  gl_FragColor = vec4(c.rgb * u_dim, c.a);
}
`;

export const SplitFlap = {
  mounted() {
    this.canvas = this.el;
    this.digits = this.parse(this.el.dataset.value);
    // What the tiles currently display: zeros until the boot run-up lands.
    this.shown = this.digits.map(() => 0);
    this.flips = new Map();
    this.gl = this.canvas.getContext("webgl", { alpha: true, antialias: false, premultipliedAlpha: true });
    if (!this.gl) {
      this.el.dataset.unsupported = "true";
      return;
    }
    this.motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
    this.listeners = new AbortController();
    const options = { signal: this.listeners.signal };
    this.el.addEventListener("split-flap:value", (event) => this.setValue(String(event.detail.value)), options);

    this.setup();
    this.observer = new ResizeObserver(() => this.resize());
    this.observer.observe(this.canvas);
    // Geist Mono may still be loading on first paint; redraw the atlas once
    // it lands so the digits never stay in the fallback face.
    document.fonts?.load(`${GLYPH_FONT}px "Geist Mono"`).then(
      () => this.rebuildGlyphs(),
      () => {},
    );
    this.layout();
    this.resize();
    this.schedule();
  },

  destroyed() {
    cancelAnimationFrame(this.frame);
    this.observer?.disconnect();
    this.listeners?.abort();
    const gl = this.gl;
    if (gl && this.program) {
      gl.deleteProgram(this.program);
      gl.deleteBuffer(this.buffer);
      gl.deleteTexture(this.texture);
    }
  },

  parse(value) {
    return Array.from(String(value || "0"), (char) => {
      const digit = Number(char);
      return Number.isFinite(digit) ? digit : 0;
    });
  },

  // A new value only moves the target; schedule() works out the flips. A
  // longer value gains tiles on the left, which start from zero.
  setValue(value) {
    const next = this.parse(value);
    const offset = next.length - this.shown.length;
    this.shown = next.map((_, index) => (index - offset >= 0 ? this.shown[index - offset] : 0));
    this.digits = next;
    this.layout();
    this.schedule();
  },

  // Start a flip on every idle tile that is not showing its target. A tile
  // steps through the digits one flap at a time, as the drum of a real
  // board does — 4 to 8 passes 5, 6 and 7, and 8 to 1 goes round through 9
  // and 0. A tile mid-flip is left alone: render() chains the next flap
  // when the current one lands.
  schedule() {
    const now = performance.now();
    const animate = !this.motionPreference.matches;
    this.digits.forEach((digit, index) => {
      if (this.flips.has(index) || this.shown[index] === digit) return;
      if (!animate) {
        this.shown[index] = digit;
        return;
      }
      this.flips.set(index, this.nextFlip(index, now + index * STAGGER_MS));
    });
    if (this.flips.size) this.tick();
    else this.render();
  },

  // The next card for a tile: one step round the drum. Intermediate cards
  // are driven hard and stop dead; the card that reaches the target falls
  // under gravity and bounces.
  nextFlip(index, start) {
    const from = this.shown[index];
    const to = (from + 1) % 10;
    const quick = to !== this.digits[index];
    return { from, to, start, quick, theta: 0, omega: quick ? QUICK_OMEGA : OMEGA, done: false };
  },

  // Advance a card by dt seconds: gravity torque grows with the sine of the
  // angle from the top position, drag opposes the spin, and the stack at
  // half a turn is a hard stop with a little bounce.
  step(flip, dt) {
    const gravity = flip.quick ? QUICK_GRAVITY : GRAVITY;
    const h = dt / SUBSTEPS;
    for (let i = 0; i < SUBSTEPS && !flip.done; i++) {
      const press = flip.theta > Math.PI / 2 ? PRESS : 0;
      flip.omega += (gravity * Math.sin(flip.theta) + press - DRAG * flip.omega) * h;
      flip.theta += flip.omega * h;
      if (flip.theta >= Math.PI) {
        flip.theta = Math.PI;
        if (flip.quick || Math.abs(flip.omega) < REST) {
          flip.done = true;
        } else {
          flip.omega = -Math.min(RESTITUTION * flip.omega, REBOUND);
        }
      }
    }
  },

  tick() {
    cancelAnimationFrame(this.frame);
    this.render();
    if (this.flips.size) this.frame = requestAnimationFrame(() => this.tick());
    else this.last = null;
  },

  setup() {
    const gl = this.gl;
    const compile = (type, source) => {
      const shader = gl.createShader(type);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw new Error(gl.getShaderInfoLog(shader));
      }
      return shader;
    };
    this.program = gl.createProgram();
    gl.attachShader(this.program, compile(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(this.program, compile(gl.FRAGMENT_SHADER, FRAGMENT));
    gl.linkProgram(this.program);
    if (!gl.getProgramParameter(this.program, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(this.program));
    }
    gl.useProgram(this.program);

    this.buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(this.program, "a_pos");
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

    this.uniforms = {};
    for (const name of [
      "u_resolution",
      "u_quad",
      "u_tile",
      "u_scale",
      "u_layer",
      "u_glyphs",
      "u_glyph",
      "u_angle",
      "u_hinge",
      "u_focal",
      "u_dim",
    ]) {
      this.uniforms[name] = gl.getUniformLocation(this.program, name);
    }

    this.texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.uniform1i(this.uniforms.u_glyphs, 0);

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  },

  // The row is as wide as its digits: the CSS sizes the canvas from --tiles.
  layout() {
    this.el.style.setProperty("--tiles", String(this.digits.length));
    this.el.setAttribute("aria-label", this.digits.join(""));
  },

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const dpr = window.devicePixelRatio || 1;
    const width = Math.round(rect.width * dpr);
    const height = Math.round(rect.height * dpr);
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }
    // One design unit in device pixels: the row's height is one tile.
    this.scale = height / TILE_H;
    this.rebuildGlyphs();
  },

  // The glyph atlas: the ten digits, each in a 90×128 cell at the current
  // scale, Geist Mono 105 units, centred on x=45.5 with the baseline on
  // y=105 — the digit "1" in the SVG spans x 20.3…70.7 and y 30.45…105.
  rebuildGlyphs() {
    const gl = this.gl;
    if (!gl || !this.scale) return;
    const scale = this.scale;
    const atlas = document.createElement("canvas");
    atlas.width = Math.ceil(TILE_W * 10 * scale);
    atlas.height = Math.ceil(TILE_H * scale);
    const ctx = atlas.getContext("2d");
    ctx.fillStyle = "#ffffff";
    ctx.textAlign = "center";
    ctx.textBaseline = "alphabetic";
    ctx.font = `400 ${GLYPH_FONT * scale}px "Geist Mono", monospace`;
    for (let digit = 0; digit < 10; digit++) {
      ctx.fillText(String(digit), (digit * TILE_W + 45.5) * scale, 105 * scale);
    }
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, atlas);
    this.render();
  },

  render() {
    const gl = this.gl;
    if (!gl || !this.scale) return;
    const { width, height } = this.canvas;
    const now = performance.now();
    gl.viewport(0, 0, width, height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(this.program);
    gl.uniform2f(this.uniforms.u_resolution, width, height);
    gl.uniform1f(this.uniforms.u_scale, this.scale);
    gl.uniform1f(this.uniforms.u_hinge, HINGE * this.scale);
    gl.uniform1f(this.uniforms.u_focal, FOCAL * TILE_H * this.scale);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);

    const scale = this.scale;
    const tileW = TILE_W * scale;
    const tileH = TILE_H * scale;
    const half = HINGE * scale;
    const pitch = (TILE_W + GAP) * scale;

    // One quad: the body and the pins span the tile; a flap spans its half
    // so a rotation about the hinge moves only that half.
    const draw = (layer, x, top, h, digit, angle, dim) => {
      gl.uniform1i(this.uniforms.u_layer, layer);
      gl.uniform4f(this.uniforms.u_quad, x, top, tileW, h);
      gl.uniform1f(this.uniforms.u_glyph, digit);
      gl.uniform1f(this.uniforms.u_angle, angle);
      gl.uniform1f(this.uniforms.u_dim, dim);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    };

    // Frame time for the simulation, capped so a background tab does not
    // fling the cards when it comes back.
    const dt = this.last == null ? 0 : Math.min(MAX_STEP, (now - this.last) / 1000);
    this.last = now;

    this.shown.forEach((_, index) => {
      const x = index * pitch;
      gl.uniform2f(this.uniforms.u_tile, x, 0);
      let flip = this.flips.get(index);
      if (flip && now >= flip.start) {
        this.step(flip, dt);
        while (flip && flip.done) {
          // The card landed: the tile shows its new digit, and keeps going
          // if that is not the target yet (the run-up, or a target that
          // changed mid-flip).
          this.shown[index] = flip.to;
          if (this.shown[index] === this.digits[index]) {
            this.flips.delete(index);
            flip = null;
          } else {
            flip = this.nextFlip(index, now);
            this.flips.set(index, flip);
          }
        }
      }
      const digit = this.shown[index];
      // Before its turn a tile still shows the old digit on both halves.
      const pending = flip && now < flip.start;
      const topDigit = flip && !pending ? flip.to : digit;
      const bottomDigit = flip ? flip.from : digit;

      // The card past vertical is lifted off the stack by its bounce: the
      // static flap beneath sits in its shadow.
      const lift = flip && !pending && flip.theta > Math.PI / 2 ? Math.PI - flip.theta : 0;

      draw(0, x, 0, tileH, 0, 0, 1);
      draw(1, x, 0, half, topDigit, 0, 1);
      draw(2, x, half, half, bottomDigit, 0, 1 - SHADE * Math.sin(lift));

      if (flip && !pending) {
        const theta = flip.theta;
        if (theta <= Math.PI / 2) {
          // Front face: the old top half, falling toward the viewer and
          // turning away from the light.
          draw(1, x, 0, half, flip.from, theta, 1 - 0.35 * Math.sin(theta));
        } else {
          // Back face: the new bottom half landing on the stack, catching
          // the light as it tilts toward the viewer.
          draw(2, x, half, half, flip.to, -lift, 1 + GLINT * Math.sin(2 * lift));
        }
      }

      draw(3, x, 0, tileH, 0, 0, 1);
    });
  },
};
