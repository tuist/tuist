import { build } from "esbuild";
import { mkdir, copyFile } from "node:fs/promises";
await mkdir("priv/static/sdk", { recursive: true });
for (const name of [
  "bundle.js",
  "bundle.js.LICENSE.txt",
  "brady_printing_core_web.wasm",
]) {
  await copyFile(
    `node_modules/@bradycorporation/brady-web-sdk/dist/${name}`,
    `priv/static/sdk/${name}`,
  );
}
await build({
  entryPoints: ["assets/app.js", "assets/app.css"],
  bundle: true,
  minify: true,
  outdir: "priv/static/assets",
  external: ["/sdk/*"],
  nodePaths: ["deps"],
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file", ".svg": "file" },
});
