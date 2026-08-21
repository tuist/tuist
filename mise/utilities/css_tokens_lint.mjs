#!/usr/bin/env node
// Fails when CSS references a custom property that nothing defines.
//
// An undefined var() makes the whole declaration invalid at computed-value
// time, so the rule silently does nothing: no error, no warning, no style.
// This checks every custom property, not just --noora-* ones, because the
// prefix itself is a common place for the typo to hide (--nora-spacing-4,
// var(-noora-neutral-light-100), --surface-background-primary).
//
// Definitions are pooled per scope rather than per bundle, so a token defined
// in one entry point and used from another counts as defined. Shared CSS that
// ships into several bundles should carry a var() fallback for anything its
// host bundle may not define, the way prose.css does for --docs-nav-height.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const ROOT = resolve(process.argv[2] ?? ".");

// Custom properties assigned at runtime rather than declared in CSS. Anything
// listed here is treated as defined. Entries need a reason so the list stays
// reviewable instead of becoming a dumping ground for real breakage.
const RUNTIME_DEFINED = [
  {
    name: "--available-width",
    reason:
      "Set by Zag on the date picker positioner. It comes from node_modules, " +
      "so the first-party scan below cannot see it.",
  },
  {
    name: "--height",
    reason:
      "noora/css/sidebar.css expand/collapse keyframes. Nothing sets it today, " +
      "so the keyframes drop their height and the sidebar fades without sweeping. " +
      "Known gap: fixing it needs a JS scrollHeight measurement or interpolate-size.",
  },
];

const SCOPES = {
  noora: { define: ["noora/css"], check: ["noora/css"] },
  server: {
    define: ["noora/css", "server/assets"],
    check: ["server/assets"],
  },
};

// Lines that hand a value to CSS from JS or HEEx, e.g.
//   el.style.setProperty("--available-width", `${w}px`)
//   `<span data-part="dot" style="--color: ${escapeHtml(color)}"></span>`
const RUNTIME_SOURCES = ["noora/js", "noora/lib", "server/assets", "server/lib"];
const RUNTIME_EXTENSIONS = [".js", ".mjs", ".ts", ".ex", ".exs", ".heex"];

function walk(dir, extensions) {
  let out = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const entry of entries) {
    if (entry === "node_modules" || entry === "priv" || entry.startsWith(".")) continue;
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) out = out.concat(walk(full, extensions));
    else if (extensions.some((ext) => entry.endsWith(ext))) out.push(full);
  }
  return out;
}

// Blank out comments so documented examples do not register as real
// definitions or references, keeping newlines so line numbers stay true.
function stripComments(css) {
  return css.replace(/\/\*[\s\S]*?\*\//g, (match) => match.replace(/[^\n]/g, " "));
}

function definitionsIn(files) {
  const defined = new Set();
  for (const file of files) {
    const css = stripComments(readFileSync(file, "utf8"));
    for (const [, name] of css.matchAll(/(--[\w-]+)\s*:/g)) defined.add(name);
    for (const [, name] of css.matchAll(/@property\s+(--[\w-]+)/g)) defined.add(name);
  }
  return defined;
}

function referencesIn(files) {
  const refs = [];
  for (const file of files) {
    const lines = stripComments(readFileSync(file, "utf8")).split("\n");
    lines.forEach((line, index) => {
      for (const [, name] of line.matchAll(/var\(\s*(-{1,2}[\w-]+)/g)) {
        refs.push({ file, line: index + 1, name });
      }
    });
  }
  return refs;
}

function runtimeDefinitions() {
  const defined = new Set();
  for (const dir of RUNTIME_SOURCES) {
    for (const file of walk(join(ROOT, dir), RUNTIME_EXTENSIONS)) {
      for (const line of readFileSync(file, "utf8").split("\n")) {
        if (line.includes("setProperty(")) {
          for (const [, name] of line.matchAll(/setProperty\(\s*['"`](--[\w-]+)/g)) defined.add(name);
        }
        if (/style\s*[=:.]/.test(line)) {
          for (const [, name] of line.matchAll(/(--[\w-]+)\s*:/g)) defined.add(name);
        }
      }
    }
  }
  return defined;
}

function distance(a, b) {
  const rows = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 0; j <= b.length; j++) rows[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      rows[i][j] = Math.min(
        rows[i - 1][j] + 1,
        rows[i][j - 1] + 1,
        rows[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
  }
  return rows[a.length][b.length];
}

// Only suggest when the fix is near-certain: a one or two character slip, or
// a name that becomes real once namespaced. A confident wrong guess (--noora-radius-full
// is not --noora-radius-0) is worse than staying quiet.
function suggest(name, defined) {
  const bare = name.replace(/^-+/, "").toLowerCase();
  const namespaced = `--noora-${bare.replace(/^noora-/, "")}`;
  if (defined.has(namespaced) && namespaced !== name) return namespaced;

  let best = null;
  let bestDistance = Infinity;
  for (const candidate of defined) {
    const d = distance(name, candidate);
    if (d < bestDistance) {
      bestDistance = d;
      best = candidate;
    }
  }
  return bestDistance <= 2 ? best : null;
}

const requested = process.argv[3];
const scopes = requested ? [requested] : Object.keys(SCOPES);
const runtime = runtimeDefinitions();
const allowed = new Set(RUNTIME_DEFINED.map((entry) => entry.name));
let failures = 0;

for (const scope of scopes) {
  const config = SCOPES[scope];
  if (!config) {
    console.log(`Unknown scope "${scope}". Expected one of: ${Object.keys(SCOPES).join(", ")}`);
    process.exit(2);
  }

  const defined = definitionsIn(config.define.flatMap((dir) => walk(join(ROOT, dir), [".css"])));
  const refs = referencesIn(config.check.flatMap((dir) => walk(join(ROOT, dir), [".css"])));
  const undefinedRefs = refs.filter((ref) => !defined.has(ref.name) && !runtime.has(ref.name) && !allowed.has(ref.name));

  if (undefinedRefs.length === 0) {
    console.log(`${scope}: ${refs.length} custom property references, all defined`);
    continue;
  }

  console.log(`\n${scope}: ${undefinedRefs.length} reference(s) to custom properties nothing defines\n`);
  for (const ref of undefinedRefs) {
    const hint = suggest(ref.name, defined);
    console.log(`  ${relative(ROOT, ref.file)}:${ref.line}  ${ref.name}`);
    if (hint) console.log(`      did you mean ${hint}?`);
  }
  failures += undefinedRefs.length;
}

if (failures > 0) {
  console.log(
    "\nAn undefined var() invalidates the whole declaration, so these rules do nothing at runtime.",
  );
  console.log("Point each at a token that exists, or drop the declaration if it is dead.\n");
  process.exit(1);
}
