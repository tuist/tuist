# Tuist Status Page

A Cloudflare Worker (Hono + TypeScript) that renders the public status page at `status.tuist.dev`. Incident data is sourced from the Grafana Cloud Incident API and republished as HTML, JSON, RSS, and Atom. The worker is stateless — no databases, no bindings.

## Layout

```
status/
├── src/
│   ├── index.ts          # Hono app and routes
│   ├── grafana-irm.ts    # Grafana IRM client + roll-up logic
│   ├── dev/
│   │   └── fake-status.ts  # Runtime dev/demo fixture used when USE_FAKE_DATA=true
│   ├── types.ts
│   └── views/
│       ├── page.ts        # HTML rendering with hono/html; incident update bodies are rendered as safe Markdown
│       ├── feed.ts        # RSS 2.0 + Atom 1.0 renderers
│       ├── logo.ts        # Inlined five-petal Tuist mark + wordmark (from server/priv/static/marketing/images/brand)
│       ├── favicon.ts     # The marketing site's favicon set (svg + base64 ico/png) served under tuist.dev's paths
│       ├── icons.ts       # Inlined Tabler/Noora status icons used by noora-status-badge, plus RSS / external-link
│       ├── noora-css.ts   # Verbatim concat of Noora tokens.css + alert.css + badge.css + button.css + button_group.css + line_divider.css
│       ├── marketing-tokens.ts # Verbatim copy of server/assets/marketing/css/shared/tokens.css (page frame, strokes)
│       ├── wave.ts        # Inline script running the particle status wave canvases under the navbar
│       └── styles.ts      # Combines NOORA_CSS + MARKETING_TOKENS_CSS with the page's own layout CSS
├── wrangler.jsonc
├── tsconfig.json
└── package.json
```

## Common Commands

- Dev server: `mise run status:dev` (or `aube run dev` from `status/`). Hits real Grafana by default; opt into fixtures with `USE_FAKE_DATA="true"` in `.dev.vars`.
- Type check: `aube run typecheck`
- Build (dry-run deploy): `mise run status:build`
- Deploy to Cloudflare: `mise run status:deploy` (requires Cloudflare auth)

## Routes

- `GET /` — status page (HTML), with `<link rel="alternate">` autodiscovery for RSS and Atom
- `GET /api/status.json` — current snapshot as JSON
- `GET /api/debug/incidents.json` — raw upstream Grafana Incident response (active + recent), no field renaming. Gated behind `ENABLE_DEBUG_ROUTES="true"` (404 otherwise). Disabled in fake-data mode. Useful for diagnosing field-name drift.
- `GET /api/debug/fields.json` — raw `FieldsService.GetFields` response plus the configured label key. Same gate. Use this when the components list is empty to discover what your label field is actually named in Grafana.
- `GET /feed.rss` — RSS 2.0, one item per incident update (active + last 14 days)
- `GET /feed.atom` — Atom 1.0, same content as RSS
- `GET /favicon.svg`, `/favicon.ico`, `/favicon-32x32.png`, `/favicon-16x16.png` — the marketing site's favicon set
- `GET /healthz` — liveness probe

Feeds are cached for 60 seconds via `Cache-Control`.

## Configuration

Variables live in `wrangler.jsonc` under `vars`. The token must be set via `wrangler secret put` (prod) or `.dev.vars` (local) — never committed.

| Variable                      | Purpose                                                                                                                                                                                                                                                                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `USE_FAKE_DATA`               | `"true"` short-circuits the Grafana Incident API and serves the runtime fixture in `src/dev/fake-status.ts`. Defaults to `"false"` so the deployed worker hits Grafana; opt in locally by adding `USE_FAKE_DATA="true"` to `.dev.vars` when iterating on the UI without a token. |
| `STATUS_PAGE_TITLE`           | Brand name shown in the header and feed `<title>`.                                                                                                                                                                                                                               |
| `GRAFANA_INCIDENT_API_URL`    | Per-stack proxy URL: `https://<your-stack-slug>.grafana.net/api/plugins/grafana-irm-app/resources`. The regional `incident-prod-*.grafana.net` form rejects stack-scoped service account tokens (`legacy auth cannot be upgraded`), so don't use it.                             |
| `GRAFANA_INCIDENT_API_TOKEN`  | Stack-level service account token (`glsa_…`) with Viewer role. **Secret. Set with `wrangler secret put` for prod and in `status/.dev.vars` for local dev.**                                                                                                                      |
| `GRAFANA_COMPONENT_LABEL_KEY` | Name (or slug) of the Grafana Incident label field whose select options define the public components shown on the page. Default `affected_service`. Each select option contributes one component: `value` → component id, `label` → display name, `description` → subtitle.      |
| `ENABLE_DEBUG_ROUTES`         | When `"true"`, exposes `/api/debug/incidents.json` and `/api/debug/fields.json`. Unset by default so production returns 404; set in `.dev.vars` for local debugging.                                                                                                             |

### Local run

```
# status/.dev.vars (gitignored)
GRAFANA_INCIDENT_API_TOKEN="glsa_xxxxxxxxxxxx_xxxxxxxx"
# Optional overrides:
# USE_FAKE_DATA="true"   # serve fixtures instead of hitting Grafana
# GRAFANA_INCIDENT_API_URL="https://<other-stack>.grafana.net/api/plugins/grafana-irm-app/resources"
```

Then `wrangler dev` from `status/`. Outbound `fetch` from local workerd reaches Grafana directly — no `--remote` needed. Hit `/api/debug/incidents.json` to see the raw upstream payload.

### CI / Deployment

Two GitHub workflows back the project:

- `.github/workflows/status.yml` — typecheck + dry-run build on every PR that touches `status/**`.
- `.github/workflows/status-deploy.yml` — deploys the worker to Cloudflare on every push to `main` that touches `status/**` (also `workflow_dispatch`).

The deploy workflow follows the same convention as `handbook.yml` and `search-deploy.yml`: it injects `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from 1Password (`op://tuist/Cloudflare/...`) using the existing `OP_SERVICE_ACCOUNT_TOKEN` GitHub secret. **No new GitHub secrets are needed** if the 1Password Cloudflare token has Workers scope. If it currently only has Pages scope (handbook deploys to Pages), update the token in the Cloudflare dashboard to add `Account → Workers Scripts → Edit` and replace the value in 1Password.

### First production deploy

The Grafana token is a Wrangler secret stored in Cloudflare's encrypted store, **not** read from 1Password at deploy time. Set it once before the first CI deploy:

```
cd status
wrangler login                                  # one-time, opens a browser
wrangler secret put GRAFANA_INCIDENT_API_TOKEN  # paste the glsa_… value
```

After that, every push to `main` that touches `status/**` runs `mise run deploy` and publishes a new revision.

## Style

The page follows the redesigned marketing site (tuist.dev): a primary-surface page built from 1200px hairline-framed sections separated by 2px seams, a navbar bar with the 32px wordmark, a centered hero carrying the overall headline, and an open-bottom footer frame with the feed links and a theme switcher. Theme handling mirrors the marketing root layout: a head script resolves the shared `preferred-theme` localStorage key, sets `color-scheme` and stamps `data-theme` on `<html>` (Noora's shadow tokens key off `data-theme`, its colors off `color-scheme`).

Only tokens are shared with the marketing bundle, nothing else. Two verbatim copies keep the worker free of the Phoenix build:

- `views/noora-css.ts` — Noora `tokens.css` + `alert.css` + `badge.css` + `button.css` + `button_group.css` + `line_divider.css`. The hero alert, badges, the header's feed buttons and the footer theme switcher are real Noora markup (`noora-alert`, `noora-status-badge`, `noora-badge`, `noora-button`, `noora-button-group` / `noora-button-group-item`) with the same `data-*` attributes the Phoenix components emit.
- `views/marketing-tokens.ts` — `server/assets/marketing/css/shared/tokens.css` (`--marketing-page-width`, `--marketing-stroke-default`, the illustration neutral ramp). Backticks inside its CSS comments are swapped for straight quotes so the template literal survives.

To regenerate after a Noora release, from the repo root:

```
{
  echo 'export const NOORA_CSS = String.raw`'
  for f in tokens alert badge button button_group line_divider; do
    printf '\n/* %s.css */\n' "$f"
    cat "noora/css/$f.css"
  done
  echo '`;'
} > status/src/views/noora-css.ts
```

`views/marketing-tokens.ts` is regenerated the same way from `server/assets/marketing/css/shared/tokens.css` (then replace any backtick in the copied CSS with `'`). The brand marks in `views/logo.ts` are the marketing site's `tuist-logo.svg` and navbar `logo-light.svg` with their fills replaced by `data-part="petals"` / `data-part="wordmark"` hooks that `views/styles.ts` colors per theme. `views/styles.ts` owns all page layout (navbar, frames, hero, sections, incident timeline, footer).

## Components (sourced from Grafana)

The list of components shown on the page comes entirely from a Grafana Incident **label field** — the same labels you attach to incidents. There is no hardcoded list in the worker.

1. In Grafana Cloud → IRM → Settings → Labels, create (or pick) a label field. The default name expected by the worker is `affected_service` (override with `GRAFANA_COMPONENT_LABEL_KEY`).
2. For each public-facing component, add a select option to that label. The option's `value` is the component id (machine-readable, used in incident labels), `label` is the display name, `description` is the subtitle shown under the name on the page.
3. When opening an incident in Grafana, attach the label with the matching value(s). The worker matches incidents to components only when the label key equals `GRAFANA_COMPONENT_LABEL_KEY` and the value matches a known option.
4. The worst severity across all matching active incidents rolls up into the per-component status.

If `/api/status.json` returns `components: []`, hit `/api/debug/fields.json` — it returns the raw `FieldsService.GetFields` response and shows you what label keys/slugs Grafana actually exposes, so you can either rename the field or set `GRAFANA_COMPONENT_LABEL_KEY` accordingly.

In fake-data mode (`USE_FAKE_DATA=true`), the components list is the runtime fixture in `src/dev/fake-status.ts` — useful for design work without a Grafana token.

## Grafana Incident API

The client lives in `src/grafana-irm.ts`. It speaks the Twirp-style JSON-over-HTTP RPC the Grafana Incident API uses: every call is `POST <base>/api/v1/<Service>.<Method>` with `Authorization: Bearer <token>` and `Content-Type: application/json; charset=utf-8`.

It calls `IncidentsService.QueryIncidents` twice on every page load:

- active list: `queryString: "isdrill:false status:active"`
- recent list: `queryString: "isdrill:false status:resolved created:>YYYY-MM-DD"` (last 14 days)

The response shape is `{ error, incidents: [...], cursor: { hasMore, nextValue } }`. The client follows the cursor up to 5 pages defensively.

After filtering resolved incidents to the last 14 days, the client calls `KeyUpdatesService.QueryKeyUpdates` for every active and recent incident. These key updates supply the timestamped status-update timeline shown on the page and republished in the feeds. The incident summary remains a fallback for incidents without key updates. Key-update queries follow the same cursor limit as incident queries and are hydrated with at most five concurrent requests.

## Severity Mapping

Grafana Incident severity → component status (`severityToComponentStatus` in `grafana-irm.ts`):

- `critical` → `major_outage`
- `major` → `partial_outage`
- `minor` / `pending` → `degraded_performance`
- An incident labeled `maintenance` (any label value) is bumped to `maintenance` severity → `under_maintenance`, regardless of the upstream severity.

## Feed Entry Model

One feed entry per incident update — i.e. each transition (`investigating`, `identified`, `monitoring`, `resolved`) produces its own entry, sorted newest first. The entry title is `[Status] Incident title`. The `<link>` jumps to `/#<incident-id>` on the status page.

## Future Work

- Persist a 90-day daily uptime history (Workers KV cron + D1) and render the dot timeline common on hosted status pages.
