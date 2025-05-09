import a from "./fonts.css.js";
import n from "./presets/alternate.css2.js";
import p from "./presets/bluePlanet.css2.js";
import f from "./presets/deepSpace.css2.js";
import o from "./presets/default.css2.js";
import i from "./presets/elysiajs.css2.js";
import u from "./presets/fastify.css2.js";
import h from "./presets/kepler.css2.js";
import c from "./presets/mars.css2.js";
import d from "./presets/moon.css2.js";
import y from "./presets/purple.css2.js";
import T from "./presets/saturn.css2.js";
import b from "./presets/solarized.css2.js";
import { migrateThemeVariables as w } from "./utilities/legacy.js";
import { hasObtrusiveScrollbars as G } from "./utilities/hasObtrusiveScrollbars.js";
const A = [
  "alternate",
  "default",
  "moon",
  "purple",
  "solarized",
  "bluePlanet",
  "deepSpace",
  "saturn",
  "kepler",
  "elysiajs",
  "fastify",
  "mars",
  "none"
], E = {
  default: "Default",
  alternate: "Alternate",
  moon: "Moon",
  purple: "Purple",
  solarized: "Solarized",
  elysiajs: "Elysia.js",
  fastify: "Fastify",
  bluePlanet: "Blue Planet",
  saturn: "Saturn",
  kepler: "Kepler-11e",
  mars: "Mars",
  deepSpace: "Deep Space",
  none: ""
}, m = {
  alternate: n,
  default: o,
  moon: d,
  elysiajs: i,
  fastify: u,
  purple: y,
  solarized: b,
  bluePlanet: p,
  deepSpace: f,
  saturn: T,
  kepler: h,
  mars: c
}, I = () => a, K = Object.keys(m), S = (e) => e === "none" ? "" : m[e || "default"] ?? o, L = (e, l) => {
  const { fonts: s = !0, layer: r = "scalar-theme" } = l ?? {}, t = [S(e), s ? a : ""].join("");
  return r ? `@layer ${r} {
${t}}` : t;
};
export {
  n as alternateTheme,
  K as availableThemes,
  p as bluePlanetTheme,
  f as deepSpaceTheme,
  o as defaultTheme,
  i as elysiajsTheme,
  u as fastifyTheme,
  I as getDefaultFonts,
  S as getThemeById,
  L as getThemeStyles,
  G as hasObtrusiveScrollbars,
  h as keplerTheme,
  c as marsTheme,
  w as migrateThemeVariables,
  d as moonTheme,
  m as presets,
  y as purpleTheme,
  T as saturnTheme,
  b as solarizedTheme,
  A as themeIds,
  E as themeLabels
};
