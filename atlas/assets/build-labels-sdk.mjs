import { mkdir, copyFile } from "node:fs/promises";

const target = "../priv/static/assets/labels-sdk";
await mkdir(target, { recursive: true });
for (const name of [
  "bundle.js",
  "bundle.js.LICENSE.txt",
  "brady_printing_core_web.wasm",
]) {
  await copyFile(
    `node_modules/@bradycorporation/brady-web-sdk/dist/${name}`,
    `${target}/${name}`,
  );
}
