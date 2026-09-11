// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/tuist";
import { Hooks } from "./js/hooks.js";
import { initAnalytics } from "../shared/js/analytics.js";
import { mountStaticHooks } from "./js/lib/static-hooks.js";
// Individual Noora hooks rather than the prebuilt `noora` runtime: that
// runtime pulls in every hook, including the ECharts-backed chart, and was
// over half of this bundle. The marketing pages render only these.
import NooraCollapsible from "noora/hooks/Collapsible.js";
import NooraDropdown from "noora/hooks/Dropdown.js";
import NooraIconTransition from "noora/hooks/IconTransition.js";
import NooraModal from "noora/hooks/Modal.js";
import NooraPopover from "noora/hooks/Popover.js";
import NooraScrollArea from "noora/hooks/ScrollArea.js";
import NooraSelect from "noora/hooks/Select.js";
import NooraTable from "noora/hooks/Table.js";
import NooraTabs from "noora/hooks/Tabs.js";
import NooraToggle from "noora/hooks/Toggle.js";
import NooraTooltip from "noora/hooks/Tooltip.js";
import "katex/dist/katex.min.css";
import "./marketing.css";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");
// Keep this aligned with nginx.ingress.kubernetes.io/proxy-connect-timeout.
const liveSocketFallbackMs = 10000;

const NooraHooks = {
  NooraCollapsible,
  NooraDropdown,
  NooraIconTransition,
  NooraModal,
  NooraPopover,
  NooraScrollArea,
  NooraSelect,
  NooraTable,
  NooraTabs,
  NooraToggle,
  NooraTooltip,
};
const hooks = { ...NooraHooks, ...Hooks, ...colocatedHooks };

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: liveSocketFallbackMs,
  // Join/push timeout (default 10s). In dev every dynamic request pays a
  // multi-second code-reloader pass under a global lock, so the first
  // join of a page load can queue 10-25s behind the page's own requests;
  // at the default timeout the client gives up, error-loops, and
  // force-reloads the page, leaving every canvas hook unmounted. 30s lets
  // the join ride out the queue (production joins reply in milliseconds,
  // so the longer ceiling only matters under load, where waiting beats a
  // reload storm anyway).
  timeout: 30000,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks,
});
liveSocket.connect();

// The navbar and footer work before (and without) the LiveView join.
mountStaticHooks(hooks, liveSocket);

// Faro page views, including the ones LiveView navigation produces.
initAnalytics();

window.liveSocket = liveSocket;

// Server-triggered `js-exec` events allow executing a server-declared
// %Phoenix.LiveView.JS{} action declared on a given element attribute.
window.addEventListener("phx:js-exec", ({ detail }) => {
  document.querySelectorAll(detail.to).forEach((el) => {
    liveSocket.execJS(el, el.getAttribute(detail.attr));
  });
});
