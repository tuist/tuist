import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

// The core's wasm-bindgen package, which Struo builds (modules/web.star):
// `struo build LuftCoreBindings` for the dev server, and a staged copy that
// Struo's own Vite build passes in LUFT_CORE_DIR.
const core = process.env.LUFT_CORE_DIR ?? fileURLToPath(new URL("../.struo/out/LuftCoreBindings", import.meta.url));

// luft-server's `mix phx.server` runs this as a watcher and stops it by
// closing stdin; exit then, or the next start finds port 5173 taken.
if (process.env.LUFT_SERVER_WATCHER) {
  process.stdin.on("end", () => process.exit(0));
  process.stdin.resume();
}

export default defineConfig({
  resolve: { alias: { "luft-core": `${core}/luft_core.js` } },
  // The Luft server (luft-server/) serves the app on its own origin and
  // proxies this dev server in development (http://localhost:4200), as it
  // serves the build in production. Only the HMR WebSocket connects here.
  // An explicit IPv4 address: `localhost` may bind only ::1.
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    hmr: { host: "127.0.0.1", clientPort: 5173 },
    fs: { allow: [".", core] },
  },
  worker: { format: "es" },
  build: { target: "es2022" },
});
