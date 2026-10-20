# Browser RUM quality and surface-specific LCP

This is the staged replacement for the mixed-population six-hour LCP alert.
The gateway is opt-in and the new rules are paused. Nothing in this change
updates the running Grafana rules or Cloudflare filters.

## Why this changes

The September 21, 2026 investigation found a six-hour global p75 of 2.896s,
but the existing marketing view was at 1.402s. Login screens were counted in
the dashboard view. A Linux Chrome 150 cohort with a 1919×992 viewport
contributed 61 LCP samples in 61 reported sessions, with p75 19.22s; 60
samples came from login pages referring to localized docs. Removing this
cohort diagnostically reduced global p75 to 1.8765s. That is evidence of
population sensitivity, not sufficient evidence to exclude Linux visitors.

Cloudflare reinforced the uncertainty. In adaptive HTTP analytics for the
same 04:00–10:00 UTC window, 139 of 177 returned Linux Chrome 150 requests
were `likely_human`, while 29 were `likely_automated`. Three collector POSTs
matched by time, user agent and referrer were classified `likely_human`.
A different Mac Chrome 145 cohort was predominantly `automated` (465 of
477 returned requests). These are sampled request cohorts, not an exact
join of each LCP observation to a security event. Numeric bot scores were
unavailable on the zone's plan. A browser fingerprint denylist or blanket
Linux/Chrome rule would hide uncertainty rather than resolve it.

One 14.952s LCP had 14.702s TTFB, but its correlated navigation event showed
only 374ms request time and 105ms response time. TTFB includes time before
the request; a large TTFB alone does not establish a slow origin.

## Data path and trust

With `server.faro.gateway.enabled: true`, the dedicated collector Ingress
keeps `/-/faro/collect` intact and routes it to Phoenix. The endpoint plug
runs before the general body parser. It accepts same-origin POSTs, reads at
most 256 KiB with a five-second read timeout, caps each Faro collection at
500 items, and rejects compressed bodies. The current Faro 2.11 fetch
transport defaults to uncompressed JSON and browser-default same-origin
credentials. Verify this contract when upgrading the SDK.

The gateway validates the existing signed session cookie and checks its
user token through the normal account lookup (including expiry, revocation
and inactive users). It forwards JSON to the configured internal Alloy
receiver with no browser headers, cookies or authorization, no redirects,
no gateway retries, a one-second connection timeout and a two-second response
timeout. It returns 202 only when Alloy returns 2xx; failures return 503.
Browser-side retries and ambiguous delivery can still duplicate samples.
The receiver URL is operator configuration, never a field in the payload.

Every measurement receives reserved context, overwriting browser-supplied
values for these keys:

| Field in Loki after `logfmt` | Meaning |
| --- | --- |
| `context_rum_schema` | `1` for the gateway's context contract |
| `context_rum_surface` | `marketing`, `docs`, `auth`, `challenge`, `api_docs`, `dashboard_authenticated`, `dashboard_anonymous`, `other`, or `unknown` |
| `context_rum_authentication` | `authenticated` or `anonymous`, verified at collector request time |
| `context_rum_ray_id` | Validated `CF-Ray` of the collector POST, or empty when the ingress trust chain is absent |
| `context_rum_automation` | Always `unknown` in this version |
| `context_rum_quality` | `eligible`, `invalid_lcp`, `missing_session`, `missing_navigation`, `unknown_surface`, or `not_lcp` |

Surface classification uses the reported same-origin URL and server router
metadata, not `view_name`. Authentication and challenge routes are separated
before dashboard classification. The URL is still browser-reported; this
is not proof that a document was served. A signed-in collector request also
does not prove that the earlier buffered navigation was authenticated.
Authenticated automation remains possible.

`eligible` means a non-negative numeric LCP with a known surface and bounded,
nonempty session/navigation identifiers. It does **not** mean verified human.
The gateway preserves the measurement value, attribution, timestamps and
reported identifiers, including slow and incomplete samples. It fixes the
app name/environment to the server's configuration and removes optional
Faro user metadata; it adds no user/account identifier. Events and other
Faro collections continue through the same receiver.

The Ray ID is accepted only from the existing trusted Cloudflare/private
Ingress hop checks in `RemoteIp`, with the ingress-overwritten
`X-Tuist-Edge-Address`. A direct public caller cannot assert it. Store Ray IDs
and session/navigation identifiers in log fields, never as Loki stream labels.
All new rules still parse `kind` out of the line.

## Alert definitions

[`browser-rum-alert-rules.json`](browser-rum-alert-rules.json) contains six
paused Grafana-managed rule objects for the alert provisioning HTTP API.
Replace `REPLACE_WITH_LOKI_DATASOURCE_UID` and
`REPLACE_WITH_ALERTS_FOLDER_UID` with the existing stack's identifiers.
Review each resolved object before POSTing it to
`/api/v1/provisioning/alert-rules`. This array is not the Grafana file
provisioning format, which Grafana Cloud does not support. Set the new
`Browser RUM quality` group's evaluation interval to one minute in Grafana
and verify notification routing before unpausing. See the
[Grafana provisioning API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/alerting_provisioning/).

| Rule | Condition over six hours unless stated otherwise |
| --- | --- |
| LCP p75 above target by surface | p75 >2.5s, >100 eligible samples, at least 50 distinct reported sessions |
| Gateway coverage low | >5% of all raw LCP samples lack schema 1, >100 samples |
| Metadata incomplete by surface | >5% of enriched LCP samples are ineligible, >100 samples |
| Cloudflare correlation coverage low | >10% of enriched LCP samples lack a trusted Ray ID, >100 samples |
| Sample concentration by surface | >100 eligible samples from fewer than 50 reported sessions |
| Enriched LCP missing | No enriched LCP in two hours, pending for 15 minutes |

The first five rules have a 30-minute pending period. Query errors use
Grafana's Error state. Zero-filled ratios prevent an empty numerator from
becoming No Data when the denominator exists. Ingestion liveness is checked
independently of quality; retain the existing raw-ingestion missing-data rule.
Low-volume individual surfaces may have no percentile alert at all.

The p75 rule creates a distinct alert instance per surface and environment;
auth and challenge traffic no longer changes marketing's percentile.
The 2.5s value is an operational target. The 100-sample/50-session floors and
quality thresholds are **provisional**: the old sample floor was derived
from pooled traffic, not each new surface. Backtest volume and baselines
before enabling, and split rules or lengthen windows for surfaces that need
different thresholds. Browser-created session IDs are not independent humans
and this version does not deduplicate navigation reports.

Keep the raw and eligible distributions side by side. For example, raw
per-surface p75 (milliseconds) is:

```logql
quantile_over_time(0.75,
  {service_name="tuist-web"} | logfmt | kind="measurement"
  | type="web-vitals" | app_environment="prod" | lcp!=""
  | context_rum_schema="1" | unwrap lcp | __error__="" [6h]
) by (app_environment, context_rum_surface)
```

Add `| context_rum_quality="eligible"` before `unwrap` for the performance
rule's population. Count by `context_rum_quality` to explain every exclusion.
Retain the unversioned/global query while measuring gateway coverage.
Do not exclude `rum_automation="unknown"` from either distribution.

## Rollout and rollback

1. Deploy the application and receiver environment variable while keeping
   `server.faro.gateway.enabled: false` (the default). Wait until **all**
   server pods run the gateway-capable image. This avoids forwarding to old
   pods while the Deployment is rolling.
2. In a subsequent Helm rollout, enable the gateway in managed production
   values. The existing dedicated Ingress changes backend and removes its
   `/collect` rewrite. Preserve its name and path; do not add a duplicate
   collector route to the main Ingress. The chart only permits the gateway
   on `/-/faro/collect`.
3. Verify from a signed-out and signed-in browser that measurements reach
   Loki with schema 1, expected auth/surface labels and unchanged values.
   Check that no session cookie is rewritten, no identity is forwarded, and
   a collector Ray ID joins a Cloudflare event when available. Inspect 400,
   403, 413, 415 and 503 rates, receiver acceptance, volume and server DB
   load. Enrichment adds an account lookup for requests carrying a session
   token. Missing security events do not establish that a request is human.
4. Import the paused rule objects, validate their instant queries and label
   joins against actual Loki data, and backtest at least a full traffic cycle
   per surface. Collect enough history to select windows/sample floors and
   compare raw/eligible p75, sample count, distinct sessions, repeated
   session/navigation pairs, metadata coverage and Ray-ID coverage.
5. Enable quality and liveness rules, then performance rules. Keep existing
   percentile alerts until coverage and baselines are verified, then retire
   the mixed-population alerts. Rename any retained six-hour p75 alert to
   describe an operational measurement. A six-hour Faro result does not
   establish an official Core Web Vitals pass/fail: use the separate 28-day
   Chrome UX Report assessment for that statement.

Rollback by setting `server.faro.gateway.enabled: false`. This restores the
ExternalName backend and `/collect` rewrite without a receiver restart.
Pause the schema-dependent rules, keep the old raw rules, and wait for the
six-hour coverage window to clear before evaluating a subsequent rollout.
There is no data migration or new storage service.

## Follow-up boundary

This change supplies correlation and population context, not a bot detector.
A follow-up can reconcile trusted collector Ray IDs with Cloudflare Security
Events/HTTP analytics and record classification source, time and coverage.
Cloudflare joins may be sampled, unavailable or disagree with behavioral
signals; unmatched requests must remain unknown. The collector's Ray ID is
not the original document's Ray ID and cannot establish navigation timing.

Do not add fingerprint, browser-version or ASN exclusions based solely on
the September cohorts. Preserve raw measurements and expose excluded/unknown
fractions for any future classification policy. Navigation deduplication,
server-backed navigation provenance, automatic Cloudflare reconciliation and
a CrUX integration are separate follow-ups, not implemented by this draft.
