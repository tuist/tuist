// The Luft core runs here, off the page's thread. Its host calls are
// synchronous, which browsers allow only in workers (sync XHR, OPFS handles).
import init, { theme_catalog } from "luft-core";

await init();
const catalog = JSON.parse(theme_catalog()) as { themes: { name: string }[] };
postMessage({ themes: catalog.themes.map((theme) => theme.name) });
