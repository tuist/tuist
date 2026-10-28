// Particle status wave for the stage under the navbar.
//
// The canvas[data-wave] runs a particle field shaped like a tube around a
// curve whose form follows the state: a clean sinusoid for "operational" (and
// "maintenance", which only changes the ink ramp), the same sine with
// value-noise jitter for "degraded", and a torn, gappy, high-frequency band
// for "outage". Particles sit on (and just inside) the
// tube's surface; the ones facing the viewer are bigger and brighter, the
// ones on the back face smaller and dimmer, with no directional light so the
// band reads flat rather than lit from above. Each
// particle is a crisp 1-2px square on whole css pixels, repainted at a
// low, fixed cadence, its size and opacity growing with its depth toward the
// viewer, so the cloud keeps a stepped, dithered grain; particles drift along the band and slowly roll around the
// tube.
//
// Colors come from CSS at draw time: each particle is assigned one of four
// tones, read from the canvas's --wave-ink-<state>-N custom properties (each
// state's Noora color ramp, set in styles.ts), so the wave follows the theme
// without any token knowledge here.
//
// The state is the canvas's data-wave attribute. When it changes (the live
// poller in page.ts flips it as the overall status moves) the field does
// not cut: the curve blends from the old profile to the new one and the ink
// ramp cross-fades over MORPH_MS, so the same wave settles or roughens and
// changes color while the particles keep their rhythm. Under prefers-reduced-motion a single frame is drawn
// and only redrawn on resize or theme change.
export const WAVE_SCRIPT = `
(function () {
  var canvases = Array.prototype.slice.call(document.querySelectorAll("canvas[data-wave]"));
  if (!canvases.length || typeof ResizeObserver === "undefined") return;

  var DENSITY = 2.2; // particles per css px of width
  var STRAY_SHARE = 0.08; // particles flying loose around the tube
  var TUBE_SCALE = 1.2; // tube radius relative to the state's band sigma
  // Global tempo: the shape functions are written in "wave seconds"; this
  // scales wall-clock time down so the whole field drifts slowly.
  var SPEED = 0.3;
  var TONES = 4; // --wave-ink-1 … --wave-ink-4
  // Dither cadence: the field is simulated continuously but only repainted
  // this often, on whole css pixels, so it steps like a stop-motion stipple
  // instead of gliding.
  var FRAME_MS = 1000 / 24;
  var ALPHA_STEPS = 6;
  var MORPH_MS = 1800;
  var STATES = ["operational", "degraded", "outage", "maintenance"];
  // The base sinusoid's phase speed in css px per frame at 60fps (wavelength
  // 240px, angular speed 1.2 rad per wave-second). Particles drift at least
  // this fast so they ride the crests forward instead of sliding back along
  // them.
  var WAVE_SPEED = (1.2 * 240) / (Math.PI * 2) / 60;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  function hash(n) {
    var x = Math.sin(n * 12.9898) * 43758.5453;
    return x - Math.floor(x);
  }

  function noise(x) {
    var i = Math.floor(x);
    var f = x - i;
    var u = f * f * (3 - 2 * f);
    return hash(i) * (1 - u) + hash(i + 1) * u;
  }

  // Every time term is subtracted so each layer (sine, jitter, tears and
  // bursts) travels left to right along with the particle drift.
  function profile(state, x, t) {
    var k = (Math.PI * 2) / 240;
    var base = Math.sin(x * k - t * 1.2) * 22;
    if (state === "operational" || state === "maintenance") return { y: base, sigma: 6 };
    if (state === "degraded") {
      var jitter = (noise(x / 38 - t * 2.5) - 0.5) * 26 + (noise(x / 12 - t * 3) - 0.5) * 8;
      return { y: base * 0.8 + jitter, sigma: 5.5 + noise(x / 60 - t) * 5 };
    }
    var torn = noise(x / 55 - t * 3) < 0.35;
    var burst = (noise(x / 14 - t * 5) - 0.5) * 44 + (noise(x / 6 - t * 8) - 0.5) * 10;
    return { y: base * 0.35 + burst, sigma: torn ? 1.2 : 4 + noise(x / 20 - t * 4) * 9 };
  }

  function easeInOut(u) {
    return u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2;
  }

  // Profile blended between the canvas's previous and current state.
  function blendedProfile(canvas, x, t) {
    var to = profile(canvas._state, x, t);
    if (canvas._mix >= 1) return to;
    var from = profile(canvas._fromState, x, t);
    var m = easeInOut(canvas._mix);
    return { y: from.y + (to.y - from.y) * m, sigma: from.sigma + (to.sigma - from.sigma) * m };
  }

  // Resolve a CSS color string to RGBA through a scratch canvas, so oklch()
  // and light-dark() results can be interpolated numerically.
  var scratch = document.createElement("canvas");
  scratch.width = scratch.height = 1;
  var scratchCtx = scratch.getContext("2d", { willReadFrequently: true });
  var rgbaCache = {};
  function toRgba(color) {
    if (rgbaCache[color]) return rgbaCache[color];
    scratchCtx.clearRect(0, 0, 1, 1);
    scratchCtx.fillStyle = color;
    scratchCtx.fillRect(0, 0, 1, 1);
    var d = scratchCtx.getImageData(0, 0, 1, 1).data;
    return (rgbaCache[color] = [d[0], d[1], d[2], d[3] / 255]);
  }

  function palette(style, state) {
    var colors = [];
    for (var n = 1; n <= TONES; n++) {
      colors.push(toRgba(style.getPropertyValue("--wave-ink-" + state + "-" + n).trim() || style.color));
    }
    return colors;
  }

  // Current ink strings for the canvas: the target palette, cross-faded from
  // the previous one while a morph is running.
  function inks(canvas, style) {
    var to = palette(style, canvas._state);
    var m = canvas._mix >= 1 ? 1 : easeInOut(canvas._mix);
    var out = [];
    for (var n = 0; n < TONES; n++) {
      var c = to[n];
      if (m < 1) {
        var f = palette(style, canvas._fromState)[n];
        c = [f[0] + (c[0] - f[0]) * m, f[1] + (c[1] - f[1]) * m, f[2] + (c[2] - f[2]) * m, f[3] + (c[3] - f[3]) * m];
      }
      out.push("rgba(" + Math.round(c[0]) + ", " + Math.round(c[1]) + ", " + Math.round(c[2]) + ", " + c[3].toFixed(3) + ")");
    }
    return out;
  }

  function stateOf(canvas) {
    var state = canvas.getAttribute("data-wave");
    return STATES.indexOf(state) === -1 ? "operational" : state;
  }

  function trackState(canvas) {
    canvas._state = stateOf(canvas);
    canvas._fromState = canvas._state;
    canvas._mix = 1;
    new MutationObserver(function () {
      var next = stateOf(canvas);
      if (next === canvas._state) return;
      // Start the morph from wherever the current blend is, so a change
      // mid-morph doesn't snap.
      canvas._fromState = canvas._mix >= 1 ? canvas._state : canvas._fromState;
      canvas._state = next;
      canvas._mix = 0;
      canvas._morphStart = performance.now();
      sync();
    }).observe(canvas, { attributes: true, attributeFilter: ["data-wave"] });
  }

  function seedParticles(canvas, width) {
    var count = Math.round(width * DENSITY);
    var particles = new Array(count);
    for (var i = 0; i < count; i++) {
      var stray = hash(i * 5 + 4) < STRAY_SHARE;
      // Radial position: most particles on the surface, a few inside for body.
      var inner = hash(i * 5 + 6);
      particles[i] = {
        x: hash(i * 5 + 2) * width,
        theta: hash(i * 5 + 1) * Math.PI * 2,
        radius: stray ? 1.6 + hash(i * 5 + 7) * 1.6 : 1 - inner * inner * inner * 0.7,
        roll: (hash(i * 5 + 3) - 0.5) * 0.9, // radians per wave-second around the tube
        drift: WAVE_SPEED * (1 + hash(i * 5 + 8) * 0.6), // px per frame at 60fps, scaled by SPEED
        stray: stray,
        tone: Math.floor(hash(i * 5 + 9) * TONES),
      };
    }
    canvas._particles = particles;
    canvas._seedWidth = width;
  }

  function draw(canvas, t, dt) {
    var width = canvas.clientWidth;
    var height = canvas.clientHeight;
    if (!width || !height) return;
    var dpr = window.devicePixelRatio || 1;
    var pixelWidth = Math.round(width * dpr);
    var pixelHeight = Math.round(height * dpr);
    if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
      canvas.width = pixelWidth;
      canvas.height = pixelHeight;
    }
    if (!canvas._particles || canvas._seedWidth !== width) seedParticles(canvas, width);

    var ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);

    var style = getComputedStyle(canvas);
    if (canvas._mix < 1) {
      canvas._mix = Math.min(1, (performance.now() - canvas._morphStart) / MORPH_MS);
    }
    var colors = inks(canvas, style);
    var mid = height / 2;
    var particles = canvas._particles;
    var step = dt * 60;

    // Advance and place every particle, then paint far to near so the
    // brighter front face sits on top of the dimmer back face.
    var placed = [];
    for (var i = 0; i < particles.length; i++) {
      var p = particles[i];
      p.x += p.drift * step;
      if (p.x >= width) p.x -= width;
      p.theta += p.roll * dt;

      var curve = blendedProfile(canvas, p.x, t);
      var tube = curve.sigma * TUBE_SCALE;
      var ny = Math.sin(p.theta);
      var nz = Math.cos(p.theta);
      var y = mid + curve.y + ny * p.radius * tube;
      if (y < -4 || y > height + 4) continue;

      // Depth toward the viewer sets size and opacity. It depends only on
      // cos(theta), so it is symmetric top-to-bottom and the band stays flat
      // (no lit top / shadowed bottom); the rolling motion is unchanged.
      var toward = (nz + 1) / 2; // 0 = back of the tube, 1 = nearest the viewer
      // Size in three steps and opacity in six keep the dither grain.
      var alpha = Math.ceil((0.3 + 0.7 * toward) * ALPHA_STEPS) / ALPHA_STEPS;
      var size = toward < 0.35 ? 1 : toward < 0.7 ? 1.5 : 2;
      if (p.stray) {
        alpha *= 0.5;
        size = 1;
      }
      placed.push({
        x: Math.round(p.x),
        y: Math.round(y),
        z: nz,
        alpha: alpha,
        size: size,
        tone: p.tone,
      });
    }
    placed.sort(function (a, b) {
      return a.z - b.z;
    });
    for (var j = 0; j < placed.length; j++) {
      var q = placed[j];
      ctx.fillStyle = colors[q.tone];
      ctx.globalAlpha = Math.min(1, q.alpha);
      ctx.fillRect(q.x - q.size / 2, q.y - q.size / 2, q.size, q.size);
    }
    ctx.globalAlpha = 1;
  }

  var start = performance.now();
  var last = start;
  function drawAll(now) {
    var t = ((now - start) / 1000) * SPEED;
    var dt = Math.min((now - last) / 1000, 0.1) * SPEED;
    last = now;
    for (var i = 0; i < canvases.length; i++) draw(canvases[i], t, dt);
  }

  var running = false;
  var lastPaint = 0;
  function frame(now) {
    if (!running) return;
    if (now - lastPaint >= FRAME_MS) {
      lastPaint = now;
      drawAll(now);
    }
    requestAnimationFrame(frame);
  }
  function redraw() {
    drawAll(performance.now());
  }
  function sync() {
    var shouldRun = !reduceMotion.matches && document.visibilityState === "visible";
    if (shouldRun && !running) {
      running = true;
      last = performance.now();
      requestAnimationFrame(frame);
    } else if (!shouldRun) {
      running = false;
      // Static mode: skip the morph and paint the new state directly.
      for (var i = 0; i < canvases.length; i++) canvases[i]._mix = 1;
      redraw();
    }
  }

  for (var c = 0; c < canvases.length; c++) trackState(canvases[c]);
  sync();
  reduceMotion.addEventListener("change", sync);
  document.addEventListener("visibilitychange", sync);
  var observer = new ResizeObserver(redraw);
  for (var i = 0; i < canvases.length; i++) observer.observe(canvases[i]);
  new MutationObserver(redraw).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
})();
`;
