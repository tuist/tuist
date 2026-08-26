// Guards CSS against referencing custom properties that nothing defines.
//
// An undefined var() makes the whole declaration invalid at computed-value
// time, so the rule silently does nothing: no error, no warning, no style.
//
// Three rules cover that between them, because the unknown-property rule alone
// has two blind spots. It stops reporting as soon as a var() has a fallback,
// and it only recognises an argument as a custom property when it starts with
// two dashes. The two disallowed-value patterns below close both.

import { readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));

function cssFiles(directory) {
  let out = [];
  for (const entry of readdirSync(directory)) {
    if (entry === "node_modules" || entry.startsWith(".")) continue;
    const full = join(directory, entry);
    if (statSync(full).isDirectory()) out = out.concat(cssFiles(full));
    else if (entry.endsWith(".css")) out.push(full);
  }
  return out;
}

const nooraTokens = cssFiles(resolve(ROOT, "noora/css"));
const serverTokens = cssFiles(resolve(ROOT, "server/assets"));

// Custom properties assigned at runtime rather than declared in CSS. Each entry
// needs a reason so this stays reviewable instead of becoming a place to
// silence real breakage.
const runtimeProperties = {
  customProperties: {
    // Set by Zag on the date picker positioner, from node_modules.
    "--available-width": "",
    // Set inline per chart series by noora/js/Chart.js.
    "--color": "",
    // noora/css/sidebar.css expand and collapse keyframes. Nothing sets it
    // today, so the keyframes drop their height and the sidebar fades without
    // sweeping. Known gap: fixing it needs a JS scrollHeight measurement or
    // interpolate-size.
    "--height": "",
    // Measured and set by server/assets/app/js/RunnerVNCClient.js once the
    // session reports its geometry.
    "--runner-vnc-width": "",
    "--runner-vnc-height": "",
    "--runner-vnc-aspect-ratio": "",
  },
};

// Properties whose hardcoded fallback is deliberate: either a value JS supplies
// after first paint, or one a sibling bundle legitimately does not define.
const FALLBACK_ALLOWED = ["docs-nav-height", "runner-vnc-"];

// The whitespace after the comma sits inside the lookahead on purpose. Written
// as `,\s*(?!var\()` the `\s*` backtracks to zero and the assertion is tested
// against the space rather than the value, so token-to-token fallbacks match.
const noHardcodedTokenFallback = `/var\\(\\s*--(?!${FALLBACK_ALLOWED.join("|")})[\\w-]+\\s*,(?!\\s*var\\()/`;

// `var(-name)` rather than `var(--name)`. The unknown-property rule skips these
// entirely, since it only treats two-dash arguments as custom properties.
const noSingleDashReference = "/var\\(\\s*-[a-zA-Z]/";

const sharedRules = {
  "declaration-property-value-disallowed-list": [
    { "/.*/": [noHardcodedTokenFallback, noSingleDashReference] },
    {
      message:
        "A design token must not carry a hardcoded fallback, and a custom property needs two " +
        "leading dashes. Both hide a var() that never resolves, which drops the whole declaration.",
    },
  ],
};

export default {
  plugins: ["stylelint-value-no-unknown-custom-properties"],
  rules: {},
  overrides: [
    // Checked against only its own tokens, so the published package stays
    // self-contained.
    {
      files: ["noora/css/**/*.css"],
      rules: {
        ...sharedRules,
        "csstools/value-no-unknown-custom-properties": [true, { importFrom: [...nooraTokens, runtimeProperties] }],
      },
    },
    {
      files: ["server/assets/**/*.css"],
      rules: {
        ...sharedRules,
        "csstools/value-no-unknown-custom-properties": [
          true,
          { importFrom: [...nooraTokens, ...serverTokens, runtimeProperties] },
        ],
      },
    },
  ],
};
