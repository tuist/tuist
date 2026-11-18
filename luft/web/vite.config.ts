import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

// The core's wasm-bindgen package, which Once builds (modules/web.star):
// `once build LuftCoreBindings` for the dev server, and a staged copy that
// Once's own Vite build passes in LUFT_CORE_DIR.
const core = process.env.LUFT_CORE_DIR ?? fileURLToPath(new URL("../.once/out/LuftCoreBindings", import.meta.url));

export default defineConfig({
  resolve: { alias: { "luft-core": `${core}/luft_core.js` } },
  server: { fs: { allow: [".", core] } },
  worker: { format: "es" },
  build: { target: "es2022" },
});
