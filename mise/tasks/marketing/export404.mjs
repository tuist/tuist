#!/usr/bin/env node
//MISE description="Refresh the offline DocC 404 from a local marketing server"

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const origin = new URL(process.argv[2] || "http://127.0.0.1:8236");
if (!['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname)) {
  throw new Error("Export from a local source checkout, not the production website");
}
const response = await fetch(new URL("/this-page-does-not-exist/no-such-route/404", origin), {
  headers: { "accept-language": "en" },
  signal: AbortSignal.timeout(15000),
});
const html = await response.text();
if (response.status !== 404 || !html.includes('id="marketing-not-found"')) {
  throw new Error(`Expected the local marketing 404, received ${response.status}`);
}
const body = html.match(/<body[^>]*>([\s\S]*)<\/body>/i)?.[1];
if (!body) throw new Error("The marketing response has no body");

const temporary = mkdtempSync(join(tmpdir(), "tuist-marketing-404-"));
try {
  const marketing = join(root, "server/assets/marketing");
  const hooks = ["DitherTexture", "NotFoundOutline", "NavbarDropdown", "NavbarMegaMenu", "MobileMenu",
    "MobileMenuDropdown", "LogoContextMenu", "ThemeSwitcher"];
  const entry = hooks.map(name => {
    const file = name.replace(/[A-Z]/g, (letter, index) => `${index ? "-" : ""}${letter.toLowerCase()}`);
    return `import { ${name} } from ${JSON.stringify(join(marketing, "js/hooks", `${file}.js`))};`;
  }).join("\n") + `
import { mountStaticHooks } from ${JSON.stringify(join(marketing, "js/lib/static-hooks.js"))};
import { applyPreferredTheme, getPreferredTheme } from ${JSON.stringify(join(marketing, "js/lib/theme.js"))};
applyPreferredTheme(getPreferredTheme());
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => applyPreferredTheme(getPreferredTheme()));
// The static export needs no LiveView/Zag runtime. Native language selection
// retains the original locale links and the shared theme/nav/canvas hooks.
for (const el of document.querySelectorAll('[data-static-hook="NooraDropdown"]')) {
  const select = document.createElement('select');
  select.setAttribute('aria-label', 'Language');
  for (const link of el.querySelectorAll('a[href]')) {
    const option = new Option(link.textContent.trim(), link.href);
    option.selected = link.dataset.value === 'en';
    select.add(option);
  }
  select.addEventListener('change', () => location.assign(select.value));
  el.replaceChildren(select);
  el.removeAttribute('data-static-hook');
}
const hooks = { ${hooks.join(", ")} };
for (const el of document.querySelectorAll('[phx-hook]')) {
  const name = el.getAttribute('phx-hook');
  if (hooks[name]) el.dataset.staticHook = name;
}
mountStaticHooks(hooks);
`;
  writeFileSync(join(temporary, "404.js"), entry);

  const styles = [
    "noora/css/tokens.css", "noora/css/button.css", "noora/css/button_group.css", "noora/css/dropdown.css",
    "noora/css/icon.css", "noora/css/badge.css",
    "server/assets/marketing/css/shared/tokens.css", "server/assets/marketing/css/shared/pages.css",
    "server/assets/marketing/css/layouts/components/dropdown.css",
    "server/assets/marketing/css/layouts/components/navbar.css",
    "server/assets/marketing/css/layouts/components/footer.css",
    "server/assets/marketing/css/layouts/components/banner.css",
    "server/assets/marketing/css/routes/not-found.css", "server/assets/marketing/css/outline-mode.css"
  ];
  // Reuse the shared base rules without unrelated routes, charts, or LiveView CSS.
  const base = readFileSync(join(marketing, "marketing.css"), "utf8").replace(/^@import .*;\s*$/gm, "");
  writeFileSync(join(temporary, "404.css"), styles.map(path => `@import ${JSON.stringify(join(root, path))};`).join("\n") + base + `
.noora-dropdown > select { border: 1px solid var(--marketing-stroke-default); border-radius: var(--noora-radius-3); background: var(--noora-surface-background-primary); color: var(--noora-surface-label-primary); padding: var(--noora-spacing-3); font: var(--noora-font-body-medium); }
`);
  const esbuild = join(root, `server/_build/esbuild-${process.platform}-${process.arch}`);
  for (const extension of ["js", "css"]) {
    execFileSync(esbuild, [join(temporary, `404.${extension}`), "--bundle", "--minify",
      `--outfile=${join(temporary, `built.${extension}`)}`], { stdio: "inherit" });
  }
  const font = (name, family, weight) => `@font-face{font-family:'${family}';font-style:normal;font-weight:${weight};font-display:swap;src:url(data:font/woff2;base64,${readFileSync(join(root, `server/priv/static/fonts/${name}.woff2`)).toString("base64")}) format('woff2')}`;
  const css = font("InterVariable", "Inter Variable", "100 900") + font("GeistMono-latin", "Geist Mono", "400 700") + readFileSync(join(temporary, "built.css"), "utf8");
  const script = readFileSync(join(temporary, "built.js"), "utf8").replaceAll("</script", "<\\/script");
  const output = `<!doctype html>
<!-- Generated from the marketing 404. Refresh: mise run marketing:export404 -- http://127.0.0.1:8236 -->
<html lang="en" dir="ltr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta name="robots" content="noindex, nofollow"><base href="https://tuist.dev/"><title>Page not found · Tuist</title><style>${css}</style></head><body>${body.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")}<script>${script}</script></body></html>\n`;
  const destination = join(root, "assets/marketing/404.html");
  mkdirSync(dirname(destination), { recursive: true });
  const normalized = output.replace(/[\t ]+$/gm, "");
  writeFileSync(destination, normalized);
  console.log(`Exported ${destination} (${Buffer.byteLength(normalized)} bytes)`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
