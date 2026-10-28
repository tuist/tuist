# Status page

Stateless Hono/TypeScript Cloudflare Worker backed by Grafana IRM. It serves HTML,
JSON, RSS, and Atom; there is no database or hardcoded component list.

## Development

Run from `status/`:

- `mise run dev` starts Wrangler against real Grafana data by default. Put
  `USE_FAKE_DATA="true"` in gitignored `.dev.vars` for the runtime fixture in
  `src/dev/fake-status.ts`.
- Validate with `aube run typecheck`, `aube run test`, and `mise run build`
  (dry-run deploy only).
- Configuration defaults live in `wrangler.jsonc`. Keep the Grafana token in
  `.dev.vars` locally or a Wrangler secret in production, never in source.
- Use the stack proxy URL (`https://<stack>.grafana.net/api/plugins/grafana-irm-app/resources`),
  not regional `incident-prod-*` URLs, with stack-scoped service-account tokens.
- Debug endpoints require `ENABLE_DEBUG_ROUTES="true"` and are disabled in fake
  mode. `/api/debug/fields.json` diagnoses empty component lists;
  `/api/debug/incidents.json` exposes raw upstream field names.

## Contracts

- Components come from the select options of `GRAFANA_COMPONENT_LABEL_KEY`
  (default `affected_service`). Match incidents by both label key and known value;
  use the worst active severity for each component.
- `critical` → major outage, `major` → partial outage, `minor`/`pending` → degraded.
  A `maintenance` label overrides upstream severity.
- Feeds contain one entry per incident update, newest first, with an incident
  anchor link; retain RSS/Atom autodiscovery and the 60-second cache policy.
- Hydrate active/recent incidents with `KeyUpdatesService.QueryKeyUpdates` for
  timestamped page/feed updates; summaries are only a fallback. Keep the 14-day
  resolved window, five-page cursor cap, and at most five concurrent hydrations.
- Resolve each update's historical `statusID` through `StatusService.QueryOrgStatuses`
  when incidents are present. Unknown or missing IDs fall back to the update's
  title, never the incident's current status.
- Render incident-update bodies as safe Markdown.
- Plain HTML must match Noora class names and `data-*` attributes. Keep
  `src/views/noora-css.ts` a verbatim concatenation of Noora's `tokens`, `alert`,
  `badge`, `button`, `button_group`, and `line_divider` CSS, in that order.
- `src/views/marketing-tokens.ts` copies `server/assets/marketing/css/shared/tokens.css`
  verbatim except backticks become straight quotes for its template literal.
  Brand/favicons come from marketing assets; logo fills use petal/wordmark theme
  hooks. Custom layout stays in `src/views/styles.ts`, without a Phoenix build.
- Match marketing's 1200px hairline-framed sections, 2px seams, 32px navbar wordmark,
  centered hero, and open-bottom footer with feeds/theme switcher. A head script
  resolves shared `preferred-theme`, setting both `color-scheme` and `data-theme`.

CI checks and deployment are defined in `.github/workflows/status.yml` and
`.github/workflows/status-deploy.yml`. The Grafana token is a separately provisioned
Wrangler secret, not injected by the deployment's Cloudflare credentials.
