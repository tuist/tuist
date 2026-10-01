/*
 * Dotted globe (cache "Low latency, everywhere" card): a slowly spinning
 * sphere of small squares — Natural Earth land as a dense field of dots,
 * a sparse ocean grain, an optional lat/long wireframe, and a trickle of
 * faint specks lifting off the land — with pulsing purple region markers.
 *
 * Dots are anchored to the sphere and drawn as squares in a few sizes,
 * each snapped to the device pixel grid with a whole number of device
 * pixels per side, so they stay crisp on 2x and 3x screens and still
 * glide with the rotation (a device pixel is a third of a CSS pixel on
 * a phone) instead of stepping. The globe spins about the screen's vertical axis
 * (the tilt poses the map, not the axis), so every dot keeps its screen
 * row and nothing jitters up or down. Shades come from the shallow → mid
 * → deep token ramp, interleaved with a stable per-dot random so they
 * scatter instead of banding. Dragging the canvas rotates the globe
 * (trackball); under prefers-reduced-motion the globe holds a static
 * frame and emits nothing.
 *
 * Options (all data attributes):
 *   data-size:      globe radius as a fraction of min(w, h) / 2
 *   data-tilt-x:    forward tilt in radians
 *   data-tilt-z:    sideways tilt in radians
 *   data-speed:     spin in rad/s
 *   data-meridians: meridian great circles
 *   data-parallels: parallel rings
 *   data-density:   0-100 — arc spacing of the wireframe dots
 *   data-shade:     0-100 — how much dots dim on the terminator side
 *   data-land:      0-100 — share of the land points drawn
 *   data-ocean:     0-100 — ocean grain amount
 *   data-limb:      0-100 — how much dots fade and shrink toward the limb
 *                   (0 keeps the edge dense and crisp)
 *   data-points:    stipple points on the whole sphere
 *   data-dot-size:  base dot radius in CSS px
 *   data-emit:      specks per second lifting off the land (0 = none)
 *   data-emit-speed:   their rise in CSS px per second
 *   data-emit-life:    their lifetime in seconds
 *   data-emit-opacity: 0-100 — their peak opacity
 *   data-emit-direction: "up" (default) drifts specks upward like smoke;
 *                   "radial" sends each outward along the sphere's normal
 *                   where it lifted off, so they leave in every direction
 *   data-offset-x / data-offset-y: center offset in px
 *   data-markers:   JSON list of {lon, lat, active} region markers; when
 *                   absent the globe shows the default serving regions.
 *                   Inactive markers draw a dim core and no pulse.
 *   data-arc-life:  seconds an arc takes from origin to region (default 1.6)
 *   data-arc-rate:  most arcs launched per second across all origins; the
 *                   origins' request rates are scaled down to fit, and each
 *                   arc then stands for that many requests (default 12)
 *   data-arc-max:   most arcs in flight at once (default 60)
 *   data-arc-busy:  arcs a region can have in flight before an origin's
 *                   next arc goes to the nearest region that is not busy
 *                   (0 = always the origin's own region; default 0). Needs
 *                   markers with ids.
 *   data-paused:    "true" holds the frame until a motion event resumes it
 *
 * Runtime events on the canvas (dispatched by a page controller such as
 * the cache globe page's CacheGlobe hook):
 *   dither-globe:markers  detail.markers replaces the marker list; a
 *                   marker may carry an id (its region) for arc routing
 *   dither-globe:origins  detail.origins replaces the request origins: a
 *                   list of {lon, lat, to: {lon, lat}, region, rate}, each a
 *                   place requests come from, the serving region it reaches
 *                   and its requests per second. Origins draw as small
 *                   white dots on the surface and launch arcs to their
 *                   region at their rate; when an arc lands the canvas
 *                   dispatches dither-globe:arrival with detail {region,
 *                   weight} (the requests the arc stood for).
 *   dither-globe:motion   detail.paused holds or resumes the spin
 */

import { onThemeChange } from "../lib/theme.js";

function noise2(x, y) {
  let h = (Math.imul(x + 1, 374761393) + Math.imul(y + 1, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

function resolveTokenColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const resolved = getComputedStyle(probe).color;
  probe.remove();
  const c = document.createElement("canvas");
  c.width = c.height = 1;
  const ctx = c.getContext("2d");
  ctx.fillStyle = resolved;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return [r, g, b];
}

/* ---------- 3x3 rotation helpers --------------------------------- */
function matMul(a, b) {
  const o = new Array(9);
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 3; c++) {
      o[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
    }
  }
  return o;
}

function rotAxis(ax, ay, az, ang) {
  const l = Math.hypot(ax, ay, az) || 1;
  ax /= l;
  ay /= l;
  az /= l;
  const c = Math.cos(ang);
  const s = Math.sin(ang);
  const t = 1 - c;
  return [
    t * ax * ax + c,
    t * ax * ay - s * az,
    t * ax * az + s * ay,
    t * ax * ay + s * az,
    t * ay * ay + c,
    t * ay * az - s * ax,
    t * ax * az - s * ay,
    t * ay * az + s * ax,
    t * az * az + c,
  ];
}

const IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1];

/* ---------- lighting (view space, top-left-front) ----------------- */
const L = (() => {
  const v = [-0.45, 0.55, 0.72];
  const l = Math.hypot(...v);
  return v.map((x) => x / l);
})();

/* ---------- stipple points on the sphere ---------------------------
   Built lazily on first mount (this module is imported by every
   marketing page's bundle, and doing the geometry at import time held
   up first paint everywhere): a Fibonacci spiral, each point nudged by
   up to half the spacing along the surface so the lattice never reads as
   rows or moiré, classified land/ocean against a rasterized
   equirectangular mask. Rebuilt when a globe asks for another count. */
let STIP_N = 0;
let stip = null; // x, y, z, rand
let stipShade = null; // a second, independent random per dot for the shade pick
let landFlag = null;
let maskData = null;

function ensureGeometry(count) {
  if (stip && STIP_N === count) return;
  STIP_N = count;
  stip = new Float32Array(STIP_N * 4);
  stipShade = new Float32Array(STIP_N);
  const ga = Math.PI * (3 - Math.sqrt(5));
  const spacing = Math.sqrt((4 * Math.PI) / STIP_N);
  let seed = 1234567;
  const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  for (let i = 0; i < STIP_N; i++) {
    const y = 1 - ((i + 0.5) * 2) / STIP_N;
    const r = Math.sqrt(1 - y * y);
    const th = ga * i;
    const x = Math.cos(th) * r;
    const z = Math.sin(th) * r;
    // Tangent basis: t1 ⟂ the normal and the pole, t2 = n × t1.
    let t1x = -z;
    let t1z = x;
    const t1l = Math.hypot(t1x, t1z) || 1;
    t1x /= t1l;
    t1z /= t1l;
    const t2x = y * t1z;
    const t2y = z * t1x - x * t1z;
    const t2z = -y * t1x;
    const a = (rnd() - 0.5) * spacing;
    const b = (rnd() - 0.5) * spacing;
    const jx = x + t1x * a + t2x * b;
    const jy = y + t2y * b;
    const jz = z + t1z * a + t2z * b;
    const l = Math.hypot(jx, jy, jz) || 1;
    stip[i * 4] = jx / l;
    stip[i * 4 + 1] = jy / l;
    stip[i * 4 + 2] = jz / l;
    stip[i * 4 + 3] = rnd();
    stipShade[i] = rnd();
  }

  // Land classification via the mask: one native even-odd fill plus cheap
  // texel lookups, instead of point-in-polygon tests over the LAND rings
  // (which took hundreds of milliseconds). The raster is kept for later
  // rebuilds at another point count.
  const MW = 1440;
  const MH = 720;
  if (!maskData) {
    const mask = document.createElement("canvas");
    mask.width = MW;
    mask.height = MH;
    const mctx = mask.getContext("2d", { willReadFrequently: true });
    const path = new Path2D();
    for (const r of getLand()) {
      path.moveTo(((r[0] + 1800) / 3600) * MW, ((900 - r[1]) / 1800) * MH);
      for (let i = 2; i < r.length; i += 2) {
        path.lineTo(((r[i] + 1800) / 3600) * MW, ((900 - r[i + 1]) / 1800) * MH);
      }
      path.closePath();
    }
    mctx.fillStyle = "#fff";
    mctx.fill(path, "evenodd");
    maskData = mctx.getImageData(0, 0, MW, MH).data;
  }
  landFlag = new Uint8Array(STIP_N);
  for (let i = 0; i < STIP_N; i++) {
    const x = stip[i * 4];
    const y = stip[i * 4 + 1];
    const z = stip[i * 4 + 2];
    const lat = Math.asin(Math.max(-1, Math.min(1, y)));
    const lon = Math.atan2(x, z);
    const mx = Math.min(MW - 1, ((lon / Math.PI + 1) / 2) * MW) | 0;
    const my = Math.min(MH - 1, (0.5 - lat / Math.PI) * MH) | 0;
    landFlag[i] = maskData[(my * MW + mx) * 4 + 3] > 127 ? 1 : 0;
  }
}

/* ---------- world map (Natural Earth 110m land, quantized x10) ----
   Packed as a zigzag-varint delta stream (base64) instead of a JS
   number literal: the raw ring array was ~20kB of digits that survived
   minification, tripling the hook's bundle cost. Decoding reproduces
   the exact same rings (verified bit-identical), so the coastlines and
   the land mask are unchanged. Regenerate with a script that walks the
   rings emitting zigzag varints: ring count, then per ring point count,
   absolute first point, and per-point deltas, all in 0.1-degree units. */
const LAND_B64 =
  "6gEOpwm/DAsTVQIjDFgBGhAUBwrvGLUMJQEzFDIEKBUQhweXDBoJDB2PARNJCEAULiBGAAr3Er0LMgAdCy8IHAQIzxO9CyAHQQgiAAy7D50LLAEMCVsAHQxCABbZCosLBRctBRkACggtBQ8OOgoIIhwMJCmiApMJgwpDCwsNCg0fBScdMhccHRQ7Rx97GYMBAUYXUwkBDzQVugIpHg+oAR6MAQcoDvYBFhcUdQMDGIoBIOQBICQMBggVBBYQPg4oFjoHChA0C0gGCgeeASIkARoPNBAiB1QKQg9aBGIQJhheGb4CUCYDLhk2DTYMYAkQGSUVGgcXFygHFgQ6LEoIHhhKFlAAGBQiE3oDTgQ+IEQZlAEUKA9UC0QQcAV4DAYSMCGgAQIWEywJSgkkBpIBJ3IDThElJz8NMSMBERgVLgtnBychwAE51AERAGmfOAAAahIMXgdYDO4BHcABA2wMBAjVARIOIk0SfANUFD0ScwY3FgUWjgEJaBIBFtwBFpoCA5ABECATFAZKD4wBAQoILxAXHpQBE3wGEg6aARkYEGwPlgEcAhIXJhYgBRBeNlgYHAEbDRjJCrMINhEJCR0GFQ0VAj0ULyJIGSQgDgESFwyRCf0HEAcFBzUHCQo2Dgr+CuEHHwEEGCAJAwsO3BavBjoBBy0lBRkuAAoOARqEG7EGGAcdKQgJHwURIRkNMwgGFkYqICgOCgQHJKQb0wUOEwIOHBsiBAkdDwIXKw8HCQgKEAUMFQgQDgIcKToiDwYRCI4auwMfCh0gPikK8BvZAgQRFwAGEA4CCIQczwIPBBwKCw0KjhqpAgQPCQADFgoFHuoHjwIGKQ0AAhc1nwEhDRsMDToWKAc2CBgmCBwYHjQSH5ABuBaTAgYNDgYQDxRPMBsSJRQBBBUsMwonDUUzUQUhSR8bDAIKGxE7EBMmHQoCGBsRFiIBDiMnDwgRJjsWZw0lDwkRSwElFRsCHxAOEgAiL24KBwcSEA0PJg40Ag0yJFQUKkIIEQoEBwoGCgoDHCocCBoVGAEDDBgmKAgPEAwEOhUYBgoJExEJIV41FhoIUBAiFj0KqhnRAQYFDQAHDBAFCO4SywEhDBIEEA8IkhnFARUCAQwYDQq4E8kBEQEgHiwGOSEIthKhARgLLwUYEgqaE6EBAQk5AxAMLAIQ/BCHASYBBghiJRUHtwEmDhQyEQiGFXsJDQYeBA8IrhiHAQ0GDRwcIRbgF20jDyUMHgQGCgIJDAAQDgEMEAEFFwjwE0UFBREMGAUKshQ9Bg85CgQMMAUM9hdZBQUHFCEWHgkSGTz6FBcGHxYLEBYoDH4rHB8gCwYJEQEEDUY/NwolKBkKGwsCDw8FRRgdBRYWDyZTJg0LExoiDB0AIRomCiIPKsgTHB0XRQADDRIRMBAjGSJDEwAKEBcBCSgNBQIzEwICJg0OGEQSDigHLgoKjhQWCycNJgoYEBUYxBB1FQApIk94QUosBT49FgAqJwcPNi8FNy62EiQWERcBBR8RDQkxAQYVBx8UFwcHCh0CARoTFgAkDA4eAQQQIAhKTDIdJSsMGyDgE6gBAhcFEQcUBwkAFxcMABgLCCELIB4GCSIQARAQCQQRDNgMfBEDBxAEPCItCxkIwQnKARMAEBAEDxCwE84BExkLDgoYDAADCxASAREKwhK6ARkRLjwEDxcZCIYT7gEYBRUXAR4SzhP0AQYXDwYGEQkFCRwMBgsQGAcI/hKGAgMRExoYByL6EvICEgAGGw8XAB8uCQIZFxYDBw0MGwIIDBEKAxwIBwgyDAAInwrsAh8FAAogAwqBDOYCGwYcBA4JDQAWqwuOAzQFIhMHBycEDQ8TDCkCLAgVEhAGDJ4R9gIPCQ8GARIsDgkbCqUY/gIHAAAYFg8NBxa5DMgDbjFHBw4KEwYLEkUQCAQ/DTYaNAcIjQzcAxEQBAwOGwz4EsgDCQ8LIBwiCgUPKwiTDJQEFQMBCBgDCIMMlAQDDQsWEAcOhBWqBQcRBwYPDwsGChYiAAi0BcoFHxUNCi4MCtoDygU0Bx8HFwgECAq2AvwFBx81FAQKOgIMuAG4BgwNARkRBQsqFAQyhBbmBQ0nPQkbFQ0GABBRDRQPDR8LCQkIBBITFEAqPgIUJA4JKBwOGAMYCAwWBAorERMAFQrAAcwGBw8NEhIOBA8avhb0BhwEBBUbBRETHw4JFRUAAxQKDhYCDCwmGwz5CaQHIgMRBx0OCAYGBwylE8oHKwYvGAUQNAkuIyzhCPYHDREOCAwFBQUuBwUNDgQKFwkPFQIAFBcRCwAOChMEOwAKDgcEJCwoEg0RDt0UuAgUAgUVEA8lGAEQCgMeuBb2BxYhHQYLGxIVAA0PDAsNAmQLEgIcEgoHCAoEEkkOhwGWCD8JEBYJFDwaFAsVLQr+AdgICw8XFB4GBgkM8xf2CBMHDRAeChYHEQkwO5QJFRMqAhUhFAE0OxgDCxEGCYMBGQsEMBglDBYGCwoEDh4BBAwlEAMUCwkJHhYkKAAI7xmuCSUGJAICBwixDNwJBwsNCBYECuUM5gkXCREGDggcAwrpGvwJPAkPBSkGAQoUpw2iCmYnEQUpDi8TBwoZARAKCiIOAByhArIKAw0WDWUfUQoUCCsKJAopBAwOIAIeDR4MXAQM7Qu+ChUAAwoICiIBDxEiqxu0Cg4FBRA2AygRMwsJFT8WKwAJBgQIFwMKCQsHAFBmIwELCvcO5goNBUUMIA40EwiQHIgLGQYaCAANCvUbigsZAQAOMAMVB64FkQ7uCgETHBAYDQUNEg0kIAIWOgMaCQ0VDgkBCSUNMQQdIzMPDwcBCy8TExUJJx4BEiEcBHYnNgMEIywpGhwXKiAIIhwPIBcOGBYPMFYCMBkkAAYpIg8cDCAeQEEHDVohCA8WCQIXVSV/AF1DMB5IEhIJEQsMJTwFFBYOFW8vDQIBEiQQNQMCBUkjAQ0QDUkNJAApARElCwwIFQ8XBA4LGgAVDQIOBQwtb1MAGxg9BSEPAAkOFygAGBcUEwkZEDcBBwEIERMDRww3Gw8RBh0PRSA9JhcwDBgMCiJACgYNEzEJBAEnCQtOAiANB1MgKRADJBA4ExYQECIeAiAYDgUPDQQtDhAHFhgIBhAiHygAGgkMCjACDwUGCSAJAg8gCygnPgM2HxAtCgMNHQYFJAEAExAMOhMGFRgGRAk4JSAFEisHIUdRC18fTxUVMwc7HRETBzdhcS8JKxQBCRoRCB8RGR0JPQEEJQsFLwECExgCBgshEQcdIQsFDSgRBxE9MxIfMwsDEU0eDUgeJB0GEhAGIhgHCioNBgUZCwQWTgcqCAIkXgFGDBoOnAEDHhUSWThLlAEbFgYICRQgKBcKAhYQJhgMChgaGBVaGwwRDwoLEQUDDC8MHSIBCQsGABgnJAQISQxFLiUJiQE0JyAEHg0ce3wRLCEMAh9qiwELBysmARo3IhISGRQjRBcUKQxLcgEyDDYPNiADChEDJlskCR4XCgMQNSYpNDECQRqPARwVAwQNSQ8GHhYGBQZDJQ4JEQ9TKX8fjgFADhopCRkOHwcCEiUELSIeIEwODQwOCFMHPRpIEhAAAQkqAGUuDAo8ChoSahYuDdYBCY4BGYYBGg4HFA4uExwOAg84CJgBGxsJbAIUCxYKEwgMCCgCXhc+BAMMEgQgBwARDBAQAAoULRQCFhgOLgscFREJJgM06xG2CwkHLgYaCRgKIhkKCA0UJgAWBxIhRhMBBx8BDAcFBUcIkQENTx5iCG0CCQguCEEGHhZKCAipELwLEQsdDjABDPULtgs/BxsMCgouASQLWMMNuAsQDRIQNAoiFQELOgxIEQIJJgZEFSQZIwmKASMnJTccGQEBCzgZDBMFDUsUNCNfFEskOQkRCA4OTgQFBiAeAwhPGA4ENxZ1A0sIDwgUCBsABRQQEkgODwsW1w/ECzwABgUTCSAHAxEzBT8WKgQVDhYICLgWuAtJBCwKHg0Oxw6wCxUPFQILGh4OUAM1FRLpEpQLMwk3FCgkEwySAQEqDUkTGRUIxhfeCxUHRQpcAQrPDtwLCwczBiYOGgsO1hboCw8PaQMnDgoMGgR+CQyxD/4LEAcJGVUMAQ5SCBrzEPQLLgMECQsJdQshBioKdQAuGn4TGxISCBwLHv4IhgtLAikOAQo6IBECMBIFCnAYjAEMDgfPASs9JQQRJg8e5Q6GDD4FEgcFBSQJogECGg8pCZ0BAjMGCRYTCD8KCAgoAQyTEpAMAQ0PB3MHTBw6Aq4I3BCEDAQJTgQ8EQMJWRVIAwoNKgqYAQ8CDkoBIAsKCwsHOBcUFCAHeAIPEhwItAELRht4AhAHAQ8YBYoBBCQRGAYPDgoIaANWEQBPMwcoHwMNIwRJD0MjGw4zDwkILQUdIRgLARsTAQcPCAchCwcVHQMFFRsRG1gKHBIUIAZqPBAeFwELETMVDxozBzEfEA1JBQAOHQQZCX0DjQFVIAEeDyIIHBUCEQ8TCTclKUE5GwsXCi0bBRMrFQELKi8HITMNBy4QBA0QHQgMHhMGPxMWHgsKMx8TAQkJHBkQAxYOIAcCCxsDJSMUCSI1AA8LAxARBx8LAS9HNyFlGwcVCQAAFhsGMyUDDUBLCCUBIU89ARofDhEgIwgEEBEAEVMOAAwjMiUYUw0BKSAZSh8mAwsKSB9uIxcXBgIsOVwRAAMTQQUJGRsNOTklDQdtLy8REj2OARFsKQkZGAgIBQYlFhMeYQVRDBEcIws/HBssKQEQLRwTDCUEGAwDBCMsAjAuCCsmCxYZJykBGS8hOQ8DD0UfZxsRNAAgRVoLMBMML0wJAAYcEyUdLkJ3Aw8cFQxDEgsSKVBFCw0mGYIBIAEbQX+TAYcBFSkHIwwFAyEaLQZNGScpETMrEE07JwYJDTNPTy8VPwA7ERcOCR4GEjtcEWQxUAAuJEwCGiNyPU4UVAcMERYzCR8oLwNNGzMKOREdCkMyL0gjGgEcERYWHAgoEUw0WGBIAxoKHDAeFCJKC0ocoAEQDgMACRIECQkGDQslYh0KEUQVFA4AGBwMlAElKg4UDSQCEAocPgQqHQIrDQ8KJwkpDBkeChALChYSHgIIDiYBMBIiAD4VKgIaFAMMXzQeFAkIHA5REwALHgMDBy8NCwQECBMGFgwFBDMKFR8PARUtFh0XARcPBQwXAhcDDgsJARkGHDMRBAYJCwEIEQ0ADwgLHiEoAhxFJBUgEQUBEA8CDwUGGTIpEAAACTQZAwcbDAkLEAcBCRMRBwEIFg0UQSIfGAUUGQovGUMAARcrERUhCAsrJy0AEw8VFC8AAhwNCA4qCywcDnoFCgwEKCMgHQgBDjwBBRgSCS4QBhAsDhIeRAgOCg0eCCAqDAUPDAcXEwQRFAsgCiANRhYqCSAQAyAKDBIIEA8QAAYcEwQBDF4GFgoTCmcNHxIEFAcSCAxOJh0SIQUTDQQLRyENGyIXERUVBREzFwILDxcAMVInFxsDGQoNRG4yVkJYKEwIHhBKBD4NGQUWCxQGWA9cHwANNQ9nDCANAh0qCwkUDgYwCxAGCw4uFCQHDA4PDAoMDQw4BQoLFwEACw4FlAEsEAETC2oOFgsYDBUMDAieASMOCi0SCAgLFiQSDhJEAAQLEw8UEwMbFgsvKRYBNiALCggOFQIDChAUGRAkDgMOFAkHExYBCQ4iCE4JERABFH4GDwwYDJACGhgSMAgiBRsFLgE21ge6BhoTDwENGwYXIA08AgIoDwYGDg0ABBIkAhMWDwMBDwUiFwYTHhQBAA4iAgAgIwIpCy8jMEEImxGSDEEASAYFBQzuA5YMTwMOBAsIKgQkCwiREaQMNwMUCCQDCvsOmgwtAAkQPAkDBQzRD54MCAdtChQGGQxsEwq2EJ4McQc2HEILBQcW7gK6DEANMQclIxcAKQwSBkUYDxCEAQgaBwr8A8gMKAVXDW8SoAECDv4HygxFCRUEDAgtAIYBAgcDDM4PqgxhAksaXhRWHQURGssNugwYB2MVKQIVChIMJQAhEDAQBwQuAlwTEAs42Qr+DIYBCXUVLABxIXEJHAENAxAJVxkmBzULsQEGAQokBAkOQgc7EjoSIxRmBHMATxx6EC4HEAw+BNgBAJIBnQSGDX4P3QEJxAEJFQmUAQ5IC5sBFS4BJxkAFxgLPwcmCQQRFQAaESsBGAcHBTcDGhUxAjYPBg8hAycSBgsXC1IBax9RBy8bbxcbJx8PCA8TI2EQQTYNIBsSCA4NCBQYHgYMGDMLFwYGGDwDVxYWEk06NQyPAQA5ElwIgQEMAgiWARQICDUGdBgJCm4IVAU0CnYNLwoCCKQBEuYBAA==";

let LAND = null;
function getLand() {
  if (LAND) return LAND;
  const s = atob(LAND_B64);
  let p = 0;
  const next = () => {
    let u = 0;
    let sh = 0;
    let b;
    do {
      b = s.charCodeAt(p++);
      u |= (b & 127) << sh;
      sh += 7;
    } while (b & 128);
    return (u >>> 1) ^ -(u & 1);
  };
  LAND = [];
  for (let n = next(); n > 0; n--) {
    const cnt = next();
    const r = new Int16Array(cnt * 2);
    r[0] = next();
    r[1] = next();
    for (let i = 2; i < cnt * 2; i += 2) {
      r[i] = r[i - 2] + next();
      r[i + 1] = r[i - 1] + next();
    }
    LAND.push(r);
  }
  return LAND;
}

const DEG = Math.PI / 180;
function ll2xyz(lon, lat) {
  const cf = Math.cos(lat * DEG);
  return [cf * Math.sin(lon * DEG), Math.sin(lat * DEG), cf * Math.cos(lon * DEG)];
}

/* Anchored grid dots — fixed positions ON the sphere, cached per M/P/step.
   Dots are glued to the globe like paint: rotation moves them, never
   re-seats them, so lines can't crawl or "regenerate" mid-spin. */
let gridCache = { key: "", pts: null };
function gridDots(M, P, step) {
  const key = M + "|" + P + "|" + step.toFixed(4);
  if (gridCache.key === key) return gridCache.pts;
  const out = [];
  for (let j = 0; j < M; j++) {
    const lon = (j * Math.PI) / M;
    const cl = Math.cos(lon);
    const sl = Math.sin(lon);
    const n = Math.max(8, Math.round((Math.PI * 2) / step));
    for (let i = 0; i < n; i++) {
      const t = (i / n) * Math.PI * 2;
      const st = Math.sin(t);
      out.push(st * cl, Math.cos(t), st * sl);
    }
  }
  for (let k = 1; k <= P; k++) {
    const lat = -Math.PI / 2 + (k * Math.PI) / (P + 1);
    const r = Math.cos(lat);
    const y = Math.sin(lat);
    const n = Math.max(6, Math.round((Math.PI * 2 * r) / step));
    for (let i = 0; i < n; i++) {
      const t = (i / n) * Math.PI * 2;
      out.push(r * Math.cos(t), y, r * Math.sin(t));
    }
  }
  gridCache = { key, pts: new Float32Array(out) };
  return gridCache.pts;
}

/* Region markers: pulsing purple points glued to real locations on the
   sphere — they rotate with the globe and hide behind the horizon. No
   labels, just the pulse. */
const DEFAULT_MARKERS = [
  [-0.1, 51.5], // EU West — London
  [8.7, 50.1], // EU Central — Frankfurt
  [-77.5, 38.9], // US East — N. Virginia
  [-122.7, 45.5], // US West — Oregon
  [-100.4, 20.6], // Mexico — Querétaro
  [-46.6, -23.5], // Brazil — São Paulo
  [31.2, 30.0], // North Africa — Cairo
  [72.9, 19.1], // India — Mumbai
  [103.8, 1.35], // Asia — Singapore
  [139.7, 35.7], // Japan — Tokyo
  [151.2, -33.9], // Australia — Sydney
].map(([lon, lat]) => ({ point: ll2xyz(lon, lat), active: true }));

function markersFrom(list) {
  if (!Array.isArray(list)) return DEFAULT_MARKERS;
  const markers = [];
  for (const marker of list) {
    const lon = Number(marker?.lon);
    const lat = Number(marker?.lat);
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) continue;
    markers.push({ point: ll2xyz(lon, lat), active: marker.active !== false, id: marker.id });
  }
  return markers;
}

function originsFrom(list) {
  if (!Array.isArray(list)) return [];
  const origins = [];
  for (const origin of list) {
    const lon = Number(origin?.lon);
    const lat = Number(origin?.lat);
    const toLon = Number(origin?.to?.lon);
    const toLat = Number(origin?.to?.lat);
    const rate = Number(origin?.rate);
    if (![lon, lat, toLon, toLat].every(Number.isFinite) || !(rate > 0)) continue;
    origins.push({
      point: ll2xyz(lon, lat),
      to: ll2xyz(toLon, toLat),
      region: origin.region,
      rate,
      acc: Math.random(),
    });
  }
  return origins;
}

// Shortest great-circle interpolation between two unit vectors.
function slerp(a, b, t) {
  const dot = Math.max(-1, Math.min(1, a[0] * b[0] + a[1] * b[1] + a[2] * b[2]));
  const omega = Math.acos(dot);
  if (omega < 1e-4) return [a[0], a[1], a[2]];
  const so = Math.sin(omega);
  const wa = Math.sin((1 - t) * omega) / so;
  const wb = Math.sin(t * omega) / so;
  return [wa * a[0] + wb * b[0], wa * a[1] + wb * b[1], wa * a[2] + wb * b[2]];
}

function parseMarkers(raw) {
  if (!raw) return DEFAULT_MARKERS;
  try {
    return markersFrom(JSON.parse(raw));
  } catch {
    return DEFAULT_MARKERS;
  }
}

const PULSE_S = 2.4; // one ring per marker every PULSE_S seconds, staggered

// The tunable options and their data-attribute names.
const OPTIONS = [
  { key: "size", attr: "size", def: 0.92 },
  { key: "tiltX", attr: "tilt-x", def: 0.07 },
  { key: "tiltZ", attr: "tilt-z", def: -0.26 },
  { key: "speed", attr: "speed", def: 0.15 },
  { key: "meridians", attr: "meridians", def: 0 },
  { key: "parallels", attr: "parallels", def: 0 },
  { key: "density", attr: "density", def: 100 },
  { key: "shade", attr: "shade", def: 0 },
  { key: "land", attr: "land", def: 100 },
  { key: "ocean", attr: "ocean", def: 30 },
  { key: "limb", attr: "limb", def: 0 },
  { key: "points", attr: "points", def: 52000 },
  { key: "dotSize", attr: "dot-size", def: 1 },
  { key: "emit", attr: "emit", def: 0 },
  { key: "emitSpeed", attr: "emit-speed", def: 50 },
  { key: "emitLife", attr: "emit-life", def: 4.5 },
  { key: "emitOpacity", attr: "emit-opacity", def: 40 },
  { key: "emitDirection", attr: "emit-direction", def: "up" },
  { key: "arcLife", attr: "arc-life", def: 1.6 },
  { key: "arcRate", attr: "arc-rate", def: 12 },
  { key: "arcMax", attr: "arc-max", def: 60 },
  { key: "arcBusy", attr: "arc-busy", def: 0 },
  { key: "offsetX", attr: "offset-x", def: 0 },
  { key: "offsetY", attr: "offset-y", def: 0 },
];

// A dot's radius is quantized into SIZES buckets and its opacity into
// ALPHAS levels, so a frame is a few dozen Path2D fills instead of tens
// of thousands of individually styled squares.
const SIZES = 4;
const ALPHAS = 6;

export const DitherGlobe = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.raf = null;
    this.visible = false;
    this.spin = 0;
    this.pulseT = 0;
    this.drag = IDENTITY;
    this.specks = [];
    this.emitAcc = 0;
    this.origins = [];
    this.arcs = [];
    this.dt = 0;

    this.markers = parseMarkers(this.el.dataset.markers);
    this.held = this.el.dataset.paused === "true";
    this.onOrigins = (event) => {
      this.origins = originsFrom(event.detail && event.detail.origins);
      if (this.raf === null) this.render();
    };
    this.onMarkers = (event) => {
      this.markers = markersFrom(event.detail && event.detail.markers);
      if (this.raf === null) this.render();
    };
    this.onMotion = (event) => {
      this.held = Boolean(event.detail && event.detail.paused);
      if (this.held) this.stop();
      else if (this.visible && !this.reduced) this.start();
      if (this.held) this.render();
    };
    this.canvas.addEventListener("dither-globe:markers", this.onMarkers);
    this.canvas.addEventListener("dither-globe:origins", this.onOrigins);
    this.canvas.addEventListener("dither-globe:motion", this.onMotion);

    this.opts = {};
    for (const o of OPTIONS) {
      const raw = this.el.dataset[o.attr.replace(/-(\w)/g, (_, c) => c.toUpperCase())];
      if (typeof o.def === "string") {
        this.opts[o.key] = raw === undefined || raw === "" ? o.def : raw;
        continue;
      }
      const n = raw === undefined ? NaN : Number(raw);
      this.opts[o.key] = Number.isFinite(n) ? n : o.def;
    }
    ensureGeometry(Math.max(1000, Math.min(200000, Math.round(this.opts.points))));

    this.resolveColors = () => {
      this.shades = [
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-shallow"),
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-mid"),
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-deep"),
      ];
      this.markerShade = resolveTokenColor(this.host, "--marketing-cache-globe-marker");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.render();
    });

    this.resize = () => {
      const rect = this.host.getBoundingClientRect();
      // Full device resolution up to 3x: a 2x cap left phones scaling the
      // canvas up, which blurred the 1px dots.
      const dpr = Math.min(window.devicePixelRatio || 1, 3);
      this.dpr = dpr;
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.render();
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.host);
    this.resize();

    // Spin only while on screen (and never under reduced motion — the
    // globe then holds the frame it mounted with).
    this.viewObserver = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        if (this.visible && !this.reduced && !this.held) this.start();
        else this.stop();
      },
      { threshold: 0.05 },
    );
    this.viewObserver.observe(this.host);

    /* drag to rotate (trackball, view space) */
    this.dragging = false;
    this.onPointerDown = (e) => {
      this.dragging = true;
      this.lx = e.clientX;
      this.ly = e.clientY;
      this.canvas.classList.add("dragging");
      this.canvas.setPointerCapture(e.pointerId);
    };
    this.onPointerMove = (e) => {
      if (!this.dragging) return;
      const dx = e.clientX - this.lx;
      const dy = e.clientY - this.ly;
      this.lx = e.clientX;
      this.ly = e.clientY;
      const len = Math.hypot(dx, dy);
      if (len > 0) {
        const k = 3.1 / Math.min(this.w, this.h);
        this.drag = matMul(rotAxis(dy, dx, 0, len * k), this.drag);
        if (this.raf === null) this.render();
      }
    };
    this.onPointerUp = () => {
      this.dragging = false;
      this.canvas.classList.remove("dragging");
    };
    this.canvas.addEventListener("pointerdown", this.onPointerDown);
    this.canvas.addEventListener("pointermove", this.onPointerMove);
    this.canvas.addEventListener("pointerup", this.onPointerUp);
    this.canvas.addEventListener("pointercancel", this.onPointerUp);

    this.render();
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.viewObserver) this.viewObserver.disconnect();
    this.stop();
    this.canvas.removeEventListener("pointerdown", this.onPointerDown);
    this.canvas.removeEventListener("pointermove", this.onPointerMove);
    this.canvas.removeEventListener("pointerup", this.onPointerUp);
    this.canvas.removeEventListener("pointercancel", this.onPointerUp);
    this.canvas.removeEventListener("dither-globe:markers", this.onMarkers);
    this.canvas.removeEventListener("dither-globe:origins", this.onOrigins);
    this.canvas.removeEventListener("dither-globe:motion", this.onMotion);
  },

  start() {
    if (this.raf !== null) return;
    this.lastTime = performance.now();
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      const dt = Math.min((now - this.lastTime) / 1000, 0.25);
      this.lastTime = now;
      if (!this.dragging) this.spin += this.opts.speed * dt;
      this.pulseT += dt;
      this.dt = dt;
      this.render();
    };
    this.raf = requestAnimationFrame(tick);
  },

  stop() {
    if (this.raf !== null) {
      cancelAnimationFrame(this.raf);
      this.raf = null;
    }
  },

  // drag (view) * spin (view y axis) * tilt (map pose) — the spin is
  // about the screen's vertical, so each dot keeps its screen row; the
  // tilt sliders keep working after a drag.
  rotation() {
    const tilt = matMul(rotAxis(1, 0, 0, this.opts.tiltX), rotAxis(0, 0, 1, this.opts.tiltZ));
    return matMul(this.drag, matMul(rotAxis(0, 1, 0, this.spin), tilt));
  },

  /* Walk the globe's dots — wireframe and stipple — and hand each to
     plot(wx, wy, wz, n, r, scale): unit-sphere view coordinates, a signal
     n in 0..1 (how deep into the shade ramp the dot sits), the dot's own
     stable random r for the shade interleave, and a size scale (ocean
     grain draws smaller). Dots are drawn straight through the callback:
     a per-frame array of dot objects would churn the GC at 60fps. */
  drawField(plot) {
    const R = this.rotation();
    const M = Math.round(this.opts.meridians);
    const P = Math.round(this.opts.parallels);
    const spacing = 0.055 - (this.opts.density / 100) * 0.041;
    const landAmt = this.opts.land / 100;
    const oceanAmt = this.opts.ocean / 100;
    const m0 = R[0];
    const m1 = R[1];
    const m2 = R[2];
    const m3 = R[3];
    const m4 = R[4];
    const m5 = R[5];
    const m6 = R[6];
    const m7 = R[7];
    const m8 = R[8];
    const L0 = L[0];
    const L1 = L[1];
    const L2 = L[2];

    if (M > 0 || P > 0) {
      // rotate anchored wireframe dots, cull the back hemisphere, shade by
      // darkness
      const pts = gridDots(M, P, spacing);
      for (let i = 0; i < pts.length; i += 3) {
        const x = pts[i];
        const y = pts[i + 1];
        const z = pts[i + 2];
        const wz = m6 * x + m7 * y + m8 * z;
        if (wz <= 0.015) continue;
        const wx = m0 * x + m1 * y + m2 * z;
        const wy = m3 * x + m4 * y + m5 * z;
        let b = (wx * L0 + wy * L1 + wz * L2) * 0.5 + 0.5;
        if (b < 0) b = 0;
        else if (b > 1) b = 1;
        plot(wx, wy, wz, 0.35 + 0.45 * (1 - b), noise2(i, 3), 1);
      }
    }

    // surface stipple — land is a uniform sample of the continent (the
    // terminator dims dots rather than thinning them, see render), the
    // ocean a sparse field of smaller dots
    if (landAmt > 0 || oceanAmt > 0) {
      for (let i = 0; i < STIP_N; i++) {
        const x = stip[i * 4];
        const y = stip[i * 4 + 1];
        const z = stip[i * 4 + 2];
        // depth-only test first — skips ~half the points before full transform
        const wz = m6 * x + m7 * y + m8 * z;
        if (wz < 0.03) continue;
        const rnd = stip[i * 4 + 3];
        if (landFlag[i] ? landAmt <= rnd : oceanAmt * 0.35 <= rnd) continue;
        const wx = m0 * x + m1 * y + m2 * z;
        const wy = m3 * x + m4 * y + m5 * z;
        let b = (wx * L0 + wy * L1 + wz * L2) * 0.5 + 0.5;
        if (b < 0) b = 0;
        else if (b > 1) b = 1;
        const d = 1 - b;
        if (landFlag[i]) plot(wx, wy, wz, d, stipShade[i], 1);
        else plot(wx, wy, wz, d * 0.6, stipShade[i], 0.6);
      }
    }
  },

  /* Squares snapped to the device pixel grid. Each dot has its own stable
     size (so the field mixes small and large dots), optionally fades and
     shrinks toward the limb, and dims on the terminator side by the
     shade amount. Dots go into Path2D buckets by shade × size × opacity
     and each bucket is filled once. */
  render() {
    const { ctx, w, h } = this;
    if (!w || !h) return;
    ctx.clearRect(0, 0, w, h);
    const rad = (Math.min(w, h) / 2) * this.opts.size;
    const cx = w / 2 + this.opts.offsetX;
    const cy = h / 2 + this.opts.offsetY;
    const shadeAmt = this.opts.shade / 100;
    const limbAmt = Math.max(0, Math.min(1, this.opts.limb / 100));
    const maxR = this.opts.dotSize * 1.4;
    const dpr = this.dpr || 1;
    const buckets = new Array(3 * SIZES * ALPHAS);
    this.drawField((wx, wy, wz, n, r, scale) => {
      const t = Math.max(0, Math.min(1, (wz - 0.04) / 0.55));
      const fade = 1 - limbAmt * (1 - t * t * (3 - 2 * t));
      const alpha = fade * (1 - shadeAmt * 0.75 * n);
      if (alpha < 0.04) return;
      const radius = this.opts.dotSize * (0.5 + r * 0.9) * (0.5 + 0.5 * fade) * scale;
      const si = Math.min(SIZES - 1, (radius / maxR) * SIZES) | 0;
      const ai = Math.min(ALPHAS - 1, Math.ceil(alpha * ALPHAS) - 1);
      // Shade interleave off a second random derived from the dot's own,
      // so size and shade don't line up.
      const r2 = (r * 7919) % 1;
      const s = Math.min(2, n * 2);
      const lo = Math.floor(s);
      const hi = Math.min(2, lo + 1);
      const shade = s - lo > r2 ? hi : lo;
      const key = (shade * SIZES + si) * ALPHAS + ai;
      let path = buckets[key];
      if (!path) path = buckets[key] = new Path2D();
      // Whole device pixels per side, on device pixel boundaries, so the
      // square never straddles a pixel and smears.
      const side = Math.max(1, Math.round(((si + 0.5) / SIZES) * maxR * 2 * dpr)) / dpr;
      const x = Math.round((cx + wx * rad - side / 2) * dpr) / dpr;
      const y = Math.round((cy - wy * rad - side / 2) * dpr) / dpr;
      path.rect(x, y, side, side);
    });
    for (let key = 0; key < buckets.length; key++) {
      const path = buckets[key];
      if (!path) continue;
      const ai = key % ALPHAS;
      const shade = ((key / ALPHAS) | 0) / SIZES;
      const [cr, cg, cb] = this.shades[shade | 0];
      ctx.globalAlpha = (ai + 1) / ALPHAS;
      ctx.fillStyle = `rgb(${cr}, ${cg}, ${cb})`;
      ctx.fill(path);
    }
    ctx.globalAlpha = 1;
    // Specks consume the frame's dt; the arcs need it too.
    const dt = this.dt;
    this.renderSpecks(rad, cx, cy);
    this.renderOrigins(rad, cx, cy);
    this.renderArcs(rad, cx, cy, dt);
    this.renderMarkers(rad, cx, cy);
  },

  /* Request origins: small white dots on the surface, drawn in the tangent
     plane like the markers so they hug the sphere and fade at the limb. */
  renderOrigins(rad, cx, cy) {
    const origins = this.origins;
    if (!origins.length) return;
    const { ctx } = this;
    const R = this.rotation();
    const r = Math.max(1.5, rad * 0.012) / rad;
    ctx.fillStyle = "#ffffff";
    for (let i = 0; i < origins.length; i++) {
      const surface = this.surface(R, origins[i].point, rad, cx, cy);
      if (!surface) continue;
      ctx.save();
      ctx.transform(surface.a, 0, surface.b, surface.d, surface.px, surface.py);
      ctx.globalAlpha = 0.85 * surface.limb;
      ctx.beginPath();
      ctx.arc(0, 0, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  },

  /* Arcs: each origin launches arcs toward its serving region at its
     request rate (scaled so the whole globe never launches more than
     arcRate a second; an arc then stands for the requests it replaced).
     An arc is a great-circle path lifted off the sphere by a bow that
     grows with the distance. It draws itself from the origin to the region
     over arcLife seconds, its head easing along the path while the line
     behind it stays, then holds complete for a moment and fades away.
     Parts of the path behind the sphere are hidden. Landing dispatches an
     arrival event so the page can count it. Nothing launches under reduced
     motion. */
  renderArcs(rad, cx, cy, dt) {
    const arcs = this.arcs;
    const origins = this.origins;
    if (dt > 0 && !this.reduced && origins.length) {
      let total = 0;
      for (let i = 0; i < origins.length; i++) total += origins[i].rate;
      const scale = total > this.opts.arcRate ? this.opts.arcRate / total : 1;
      const weight = 1 / scale;
      // Overflow routing: with a busy threshold, count each region's arcs
      // in flight, and send an origin's next arc to the nearest region
      // under the threshold — its own if it can take it.
      const busy = this.opts.arcBusy;
      const inFlight = {};
      if (busy > 0) {
        for (let i = 0; i < arcs.length; i++) {
          if (!arcs[i].landed) inFlight[arcs[i].region] = (inFlight[arcs[i].region] || 0) + 1;
        }
      }
      for (let i = 0; i < origins.length && arcs.length < this.opts.arcMax; i++) {
        const origin = origins[i];
        origin.acc += origin.rate * scale * dt;
        while (origin.acc >= 1 && arcs.length < this.opts.arcMax) {
          origin.acc -= 1;
          const a = origin.point;
          let b = origin.to;
          let region = origin.region;
          if (busy > 0 && (inFlight[region] || 0) >= busy) {
            const routed = this.nearestFree(a, inFlight, busy);
            if (routed) {
              b = routed.point;
              region = routed.id;
            }
          }
          if (busy > 0) inFlight[region] = (inFlight[region] || 0) + 1;
          const span = Math.acos(Math.max(-1, Math.min(1, a[0] * b[0] + a[1] * b[1] + a[2] * b[2])));
          arcs.push({
            from: a,
            to: b,
            region,
            weight,
            age: 0,
            life: Math.max(0.4, this.opts.arcLife) * (0.85 + Math.random() * 0.3),
            fade: 1.1,
            landed: false,
            // Even a short hop lifts clearly off the sphere.
            bow: 0.24 + 0.36 * (span / Math.PI),
          });
        }
      }
    }
    if (!arcs.length) return;

    const { ctx } = this;
    const R = this.rotation();
    const [mr, mg, mb] = this.markerShade;
    const project = (p) => {
      const wx = R[0] * p[0] + R[1] * p[1] + R[2] * p[2];
      const wy = R[3] * p[0] + R[4] * p[1] + R[5] * p[2];
      const wz = R[6] * p[0] + R[7] * p[1] + R[8] * p[2];
      // A lifted point is behind the globe when it sits inside the disc
      // on the far side.
      const hidden = wz < 0 && wx * wx + wy * wy < 1;
      return [cx + wx * rad, cy - wy * rad, hidden];
    };
    ctx.lineCap = "round";
    ctx.lineWidth = Math.max(1, rad * 0.007);
    const steps = 28;
    for (let i = arcs.length - 1; i >= 0; i--) {
      const arc = arcs[i];
      if (dt > 0) arc.age += dt;
      if (!arc.landed && arc.age >= arc.life) {
        arc.landed = true;
        this.canvas.dispatchEvent(
          new CustomEvent("dither-globe:arrival", {
            bubbles: true,
            detail: { region: arc.region, weight: arc.weight },
          }),
        );
      }
      if (arc.age >= arc.life + arc.fade) {
        arcs[i] = arcs[arcs.length - 1];
        arcs.pop();
        continue;
      }
      // Grow to the region, hold, then fade the whole line out.
      const u = Math.min(1, arc.age / arc.life);
      const head = u * u * (3 - 2 * u);
      const settle = arc.landed ? Math.max(0, 1 - Math.max(0, arc.age - arc.life - 0.3) / (arc.fade - 0.3)) : 1;
      // Project the path, then stroke each visible run as one path with a
      // gradient from a dim tail to a bright head: one stroke per run, so
      // no joints stack up and show through the alpha.
      const points = [];
      for (let k = 0; k <= steps; k++) {
        const t = (head * k) / steps;
        const s = slerp(arc.from, arc.to, t);
        const lift = 1 + arc.bow * Math.sin(Math.PI * t);
        points.push(project([s[0] * lift, s[1] * lift, s[2] * lift]));
      }
      ctx.lineJoin = "round";
      let run = 0;
      while (run < points.length) {
        while (run < points.length && points[run][2]) run++;
        let end = run;
        while (end < points.length && !points[end][2]) end++;
        if (end - run >= 2) {
          const first = points[run];
          const lastPoint = points[end - 1];
          const gradient = ctx.createLinearGradient(first[0], first[1], lastPoint[0], lastPoint[1]);
          const tailAlpha = arc.landed ? 0.9 : 0.35 + 0.55 * (run / steps);
          const headAlpha = arc.landed ? 0.9 : 0.35 + 0.55 * ((end - 1) / steps);
          gradient.addColorStop(0, `rgba(${mr}, ${mg}, ${mb}, ${tailAlpha * settle})`);
          gradient.addColorStop(1, `rgba(${mr}, ${mg}, ${mb}, ${headAlpha * settle})`);
          ctx.strokeStyle = gradient;
          ctx.beginPath();
          ctx.moveTo(first[0], first[1]);
          for (let k = run + 1; k < end; k++) ctx.lineTo(points[k][0], points[k][1]);
          ctx.stroke();
        }
        run = end;
      }
      const last = points[points.length - 1];
      if (last && !last[2] && !arc.landed) {
        ctx.fillStyle = "#ffffff";
        ctx.globalAlpha = 0.9;
        ctx.beginPath();
        ctx.arc(last[0], last[1], Math.max(1.2, rad * 0.008), 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1;
      }
    }
  },

  // The nearest region marker (by great-circle distance from a point) with
  // fewer arcs in flight than the busy threshold, or null if every region
  // is busy.
  nearestFree(point, inFlight, busy) {
    let best = null;
    let bestDot = -2;
    for (const marker of this.markers) {
      if (marker.id == null || (inFlight[marker.id] || 0) >= busy) continue;
      const dot = point[0] * marker.point[0] + point[1] * marker.point[1] + point[2] * marker.point[2];
      if (dot > bestDot) {
        bestDot = dot;
        best = marker;
      }
    }
    return best;
  },

  // Screen placement of a point on the sphere: its limb fade and the
  // canvas transform whose unit circle is the tangent-plane ellipse there,
  // or null when it faces away.
  surface(R, point, rad, cx, cy) {
    const [x, y, z] = point;
    const wz = R[6] * x + R[7] * y + R[8] * z;
    if (wz <= 0.12) return null;
    const wx = R[0] * x + R[1] * y + R[2] * z;
    const wy = R[3] * x + R[4] * y + R[5] * z;
    let t1x = wz;
    let t1z = -wx;
    const t1l = Math.hypot(t1x, t1z) || 1;
    t1x /= t1l;
    t1z /= t1l;
    const t2x = wy * t1z;
    const t2y = wz * t1x - wx * t1z;
    const a = t1x * rad;
    const b = t2x * rad;
    const d = -t2y * rad;
    if (Math.abs(a * d) < 1e-6) return null;
    return { limb: Math.min(1, (wz - 0.12) / 0.3), a, b, d, px: cx + wx * rad, py: cy - wy * rad };
  },

  /* Specks: a slow trickle of faint squares that lift off the lit side of
     the land and drift upward with a little sway, fading in fast and out
     slowly. Time only advances from the animation tick (this.dt), so a
     static repaint — a resize, a theme change — leaves them where they
     are. Nothing is emitted under reduced motion. */
  renderSpecks(rad, cx, cy) {
    const rate = this.reduced ? 0 : this.opts.emit;
    const dt = this.dt;
    this.dt = 0;
    const specks = this.specks;
    if (rate <= 0 && specks.length === 0) return;
    const life = Math.max(0.5, this.opts.emitLife);
    if (dt > 0) {
      for (let i = specks.length - 1; i >= 0; i--) {
        const sp = specks[i];
        sp.age += dt;
        if (sp.age >= sp.life) {
          specks[i] = specks[specks.length - 1];
          specks.pop();
          continue;
        }
        sp.x += sp.vx * dt + Math.sin(sp.age * sp.sway + sp.phase) * sp.drift * dt;
        sp.y += sp.vy * dt;
      }
      this.emitAcc += rate * dt;
      const R = this.rotation();
      while (this.emitAcc >= 1 && specks.length < 600) {
        this.emitAcc -= 1;
        // A random land point on the facing hemisphere; a few tries,
        // then give up for this one.
        for (let attempt = 0; attempt < 8; attempt++) {
          const i = (Math.random() * STIP_N) | 0;
          if (!landFlag[i]) continue;
          const x = stip[i * 4];
          const y = stip[i * 4 + 1];
          const z = stip[i * 4 + 2];
          const wz = R[6] * x + R[7] * y + R[8] * z;
          if (wz < 0.3) continue;
          const wx = R[0] * x + R[1] * y + R[2] * z;
          const wy = R[3] * x + R[4] * y + R[5] * z;
          const speed = this.opts.emitSpeed * (0.7 + Math.random() * 0.6);
          let vx = 0;
          let vy = -speed;
          if (this.opts.emitDirection === "radial") {
            // Outward along the surface normal as seen on screen, which is
            // the radial direction from the globe's centre, with a little
            // scatter so specks near the centre still move.
            const len = Math.hypot(wx, wy) || 1;
            const scatter = Math.random() * Math.PI * 2;
            vx = ((wx / len) * 0.75 + Math.cos(scatter) * 0.35) * speed;
            vy = ((-wy / len) * 0.75 + Math.sin(scatter) * 0.35) * speed;
          }
          specks.push({
            x: cx + wx * rad,
            y: cy - wy * rad,
            vx,
            vy,
            drift: 2 + Math.random() * 4,
            sway: 0.6 + Math.random() * 0.8,
            phase: Math.random() * Math.PI * 2,
            size: this.opts.dotSize * (0.7 + Math.random() * 0.6),
            age: 0,
            life: life * (0.7 + Math.random() * 0.6),
          });
          break;
        }
      }
    }
    if (specks.length === 0) return;
    const { ctx } = this;
    const peak = Math.max(0, Math.min(1, this.opts.emitOpacity / 100));
    const [cr, cg, cb] = this.shades[1];
    const dpr = this.dpr || 1;
    ctx.fillStyle = `rgb(${cr}, ${cg}, ${cb})`;
    for (const sp of specks) {
      const t = sp.age / sp.life;
      const a = Math.min(1, t / 0.12) * Math.pow(1 - t, 1.3) * peak;
      if (a < 0.01) continue;
      ctx.globalAlpha = a;
      const side = Math.max(1, Math.round(sp.size * 2 * dpr)) / dpr;
      ctx.fillRect(Math.round((sp.x - side / 2) * dpr) / dpr, Math.round((sp.y - side / 2) * dpr) / dpr, side, side);
    }
    ctx.globalAlpha = 1;
  },

  /* Pulsing region markers, drawn on top of the globe as plain vector
     shapes (no dither): a solid purple core plus an expanding stroked
     ring that fades out with alpha as it grows. Core and ring live on the
     sphere's tangent plane at the marker, so they project as foreshortened
     ellipses hugging the surface — tilting with the globe and squashing
     toward the limb — instead of flat screen circles. Markers fade out
     near the horizon and under prefers-reduced-motion only the static
     cores show. Inactive markers (a region without recent activity) keep
     a smaller, dimmer core and never pulse. */
  renderMarkers(rad, cx, cy) {
    const { ctx } = this;
    const R = this.rotation();
    const [mr, mg, mb] = this.markerShade;
    const color = `rgb(${mr}, ${mg}, ${mb})`;
    const coreR = Math.max(3, rad * 0.028) / rad;
    const maxRing = coreR + 0.11;
    const markers = this.markers;
    for (let i = 0; i < markers.length; i++) {
      const { point, active } = markers[i];
      const [x, y, z] = point;
      const wz = R[6] * x + R[7] * y + R[8] * z;
      if (wz <= 0.12) continue;
      const limb = Math.min(1, (wz - 0.12) / 0.3);
      const wx = R[0] * x + R[1] * y + R[2] * z;
      const wy = R[3] * x + R[4] * y + R[5] * z;
      const px = cx + wx * rad;
      const py = cy - wy * rad;
      // Tangent basis at the marker (view space): t1 ⟂ the surface normal
      // and horizontal-ish, t2 = n × t1. Their screen projections become
      // the canvas transform, so a unit circle drawn under it lands as the
      // tangent-plane ellipse.
      let t1x = wz;
      let t1z = -wx;
      const t1l = Math.hypot(t1x, t1z) || 1;
      t1x /= t1l;
      t1z /= t1l;
      const t2x = wy * t1z;
      const t2y = wz * t1x - wx * t1z;
      const a = t1x * rad;
      const b = t2x * rad;
      const d = -t2y * rad;
      if (Math.abs(a * d) < 1e-6) continue;
      ctx.save();
      ctx.transform(a, 0, b, d, px, py);
      ctx.fillStyle = color;
      ctx.globalAlpha = active ? limb : limb * 0.45;
      ctx.beginPath();
      ctx.arc(0, 0, active ? coreR : coreR * 0.75, 0, Math.PI * 2);
      ctx.fill();
      if (active && !this.reduced) {
        // Stagger the phases so the pulses ripple around the globe
        // instead of firing in unison.
        const t = (this.pulseT / PULSE_S + i * 0.37) % 1;
        const ringR = coreR + t * (maxRing - coreR);
        ctx.strokeStyle = color;
        ctx.globalAlpha = (1 - t) * 0.9 * limb;
        ctx.lineWidth = 1.5 / rad;
        ctx.beginPath();
        ctx.arc(0, 0, ringR, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.restore();
    }
  },
};
