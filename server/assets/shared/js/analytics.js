import { initializeFaro, getWebInstrumentations } from "@grafana/faro-web-sdk";

// Real user monitoring for the marketing site, docs and dashboard. Web vitals
// (LCP among them) are captured automatically; page views are pushed on
// LiveView navigation because a `phx:navigate` does not reload the document.
//
// Sessions are not persisted across visits and no user identity is attached:
// the alerting this feeds only needs the latency distribution.
export function initAnalytics() {
  const config = globalThis.analytics;

  if (!config?.enabled || !config.collector_url) {
    return null;
  }

  const faro = initializeFaro({
    url: config.collector_url,
    app: {
      name: config.app_name,
      version: config.app_version,
      environment: config.environment,
    },
    instrumentations: getWebInstrumentations({ captureConsole: false }),
    sessionTracking: { enabled: true, persistent: false },
  });

  if (config.page_section) {
    faro.api.setView({ name: config.page_section });
  }

  faro.api.pushEvent("page_view", { pathname: window.location.pathname });

  window.addEventListener("phx:navigate", () => {
    faro.api.pushEvent("page_view", { pathname: window.location.pathname });
  });

  return faro;
}
