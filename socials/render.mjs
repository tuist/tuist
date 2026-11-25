#!/usr/bin/env node
// Renders social cards (HTML pages under socials/) to PNG with headless
// Chrome. No npm dependencies.
//
//   node socials/render.mjs <card.html> [more.html ...] [--size x|linkedin|square|all]
//
// Each card is rendered at every requested size into socials/out/,
// named <card>-<size>.png. A card can limit its sizes with
// <meta name="card-sizes" content="x,linkedin">; "all" then means those. Sizes are CSS viewports rendered at 2x, so text
// stays sharp after X and LinkedIn recompress the upload.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SIZES = {
  // X shows single images at 16:9 in the timeline.
  x: { width: 1200, height: 675 },
  // LinkedIn's recommended landscape share image (1.91:1).
  linkedin: { width: 1200, height: 627 },
  // A square post image; works on both networks.
  square: { width: 1080, height: 1080 },
};
const SCALE = 2;

const root = dirname(fileURLToPath(import.meta.url));
const outDir = join(root, "out");

function findChrome() {
  const candidates = [
    process.env.CHROME,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ];
  const agentBrowser = join(homedir(), ".agent-browser", "browsers");
  if (existsSync(agentBrowser)) {
    for (const dir of readdirSync(agentBrowser).sort().reverse()) {
      candidates.push(join(agentBrowser, dir, "chrome"));
    }
  }
  const found = candidates.find((path) => path && existsSync(path));
  if (!found) {
    console.error("Chrome not found. Set CHROME=/path/to/chrome.");
    process.exit(1);
  }
  return found;
}

const args = process.argv.slice(2);
const sizeIndex = args.indexOf("--size");
const sizeArg = sizeIndex >= 0 ? args.splice(sizeIndex, 2)[1] : "all";
const requested = sizeArg === "all" ? null : sizeArg.split(",");
for (const size of requested ?? []) {
  if (!SIZES[size]) {
    console.error(`Unknown size "${size}". Use ${Object.keys(SIZES).join(", ")} or all.`);
    process.exit(1);
  }
}
if (args.length === 0) {
  console.error("Usage: node socials/render.mjs <card.html> [...] [--size x|linkedin|square|all]");
  process.exit(1);
}

const chrome = findChrome();
mkdirSync(outDir, { recursive: true });

for (const card of args) {
  const declared = readFileSync(card, "utf8").match(/<meta name="card-sizes" content="([^"]*)"/);
  const allowed = declared ? declared[1].split(",").map((size) => size.trim()) : Object.keys(SIZES);
  const sizes = requested ?? allowed;
  const refused = sizes.filter((size) => !allowed.includes(size));
  if (refused.length > 0) {
    console.error(`${card} is not designed for ${refused.join(", ")}; it supports ${allowed.join(", ")}.`);
    process.exit(1);
  }
  const url = pathToFileURL(resolve(card)).href;
  for (const size of sizes) {
    const { width, height } = SIZES[size];
    const output = join(outDir, `${basename(card, ".html")}-${size}.png`);
    const result = spawnSync(
      chrome,
      [
        "--headless",
        "--no-sandbox",
        "--disable-gpu",
        "--hide-scrollbars",
        // Cards load Noora's CSS and the fonts from this checkout.
        "--allow-file-access-from-files",
        // Gives fonts and images time to load before the capture.
        "--virtual-time-budget=3000",
        `--force-device-scale-factor=${SCALE}`,
        `--window-size=${width},${height}`,
        `--screenshot=${output}`,
        url,
      ],
      { encoding: "utf8" },
    );
    if (result.status !== 0 || !existsSync(output)) {
      console.error(result.stderr);
      process.exit(1);
    }
    console.log(`${output} (${width * SCALE}x${height * SCALE})`);
  }
}
