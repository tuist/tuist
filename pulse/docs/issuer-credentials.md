# Issuer credentials

Pulse can trust one external credential issuer, such as Tuist in the hosted
product. The issuer signs short-lived access tokens and long-lived ingest keys,
and Pulse verifies them offline against the issuer's public keys. The tenant
and scopes come from the credential itself, so adding a tenant needs no Pulse
configuration change, and no Pulse instance calls the issuer while serving a
request.

Issuer credentials work alongside [tenant tokens](configuration.md#tenants-and-tokens)
and [workload identity](configuration.md#workload-identity). A request is
routed to the issuer verifier only when its credential is shaped like an issuer
credential (described below); everything else keeps its existing behavior.

## Configure

Set `PULSE_ISSUER_JSON` (Helm: `issuer`) to a JSON object:

| Field | Meaning |
| --- | --- |
| `issuer` | Required. Exact `iss` claim, an https URL. |
| `audience` | Required. This deployment's canonical https URL, without a trailing slash. Tokens must carry it, or `<audience>/mcp`, in `aud`. Use one audience per region to keep tokens regional. |
| `jwks_url` | Required. https URL of the issuer's JWKS. |
| `status_url` | Optional. https URL of the signed [status list](#status-list). When set, issuer credentials are refused with `503` until it has loaded once. |
| `ca_file` | Optional CA bundle for both URLs. Defaults to the system trust store. |
| `refresh_interval_seconds` | `10..3600`, default `60`. How often each instance fetches keys and the status list. |
| `key_retention_seconds` | `3600..2592000`, default `604800` (7 days). How long fetched keys stay usable while the issuer is unreachable. |
| `expired_grace_seconds` | `0..86400`, default `3600`. See [expiry](#expiry-and-outages). |
| `max_access_ttl_seconds` | `60..604800`, default `86400`. Longer-lived access tokens are rejected. |
| `max_ingest_key_ttl_seconds` | `86400..31622400`, default `31622400` (366 days). |
| `mirror` | Default `true`. With object storage configured, copy fetched keys and status to `auth/issuer/` in the bucket and fall back to them when the issuer is unreachable. |

Invalid configuration stops the node at startup. With an issuer configured,
`PULSE_TENANT_TOKENS` becomes optional.

Instances need outbound HTTPS to `jwks_url` and `status_url`. When mirroring,
they also need read and write access to `auth/issuer/` in the bucket.

## Credentials

Both credential forms are compact JWS signed with RS256 (2048-bit or larger),
ES256 (P-256) or EdDSA (Ed25519). The JWS header must carry `alg`, `kid` and
`typ`, and must not carry `crit`. The `kid` must name exactly one key in the
JWKS with a matching algorithm.

| | Access token | Ingest key |
| --- | --- | --- |
| Sent as | `Authorization: Bearer <jwt>` | `Authorization: Bearer pulse_ik_<jwt>` |
| Header `typ` | `at+jwt` | `pulse-ik+jwt` |
| Lifetime | up to `max_access_ttl_seconds` | up to `max_ingest_key_ttl_seconds` |
| `scope` | any | exactly `ingest` |
| `jti` | optional | required, for revocation |

Claims:

| Claim | Meaning |
| --- | --- |
| `iss`, `aud` | Must match the configuration. `aud` may be a string or list. |
| `sub` | Who the credential represents. 1–128 letters, digits, `_`, `.` or `-`. |
| `tenant` | The tenant the credential acts for. Use an immutable ID, never a renamable handle. Same character set. |
| `scope` | Space-separated: `ingest`, `read`, and the alerting capabilities (`alert:read`, `alert:rules:write`, `alert:audit:read`, `alert:evaluate`, `alert:preview`, `alert:import`, `alert:record`). Unknown scopes are ignored. |
| `iat`, `exp`, optional `nbf` | Integer seconds. 60 seconds of clock skew are tolerated. |
| `jti` | Credential ID. |
| `act` | Optional `{"sub": "<actor>"}` when a service acts for `sub`, for example the Tuist dashboard or Atlas acting for a user. Alert history records `<sub>.via.<actor>`. |
| `principal_type` | Optional `human`, `agent` or `service`. Defaults to `agent` with `act`, otherwise `service`. |

Keep tokens under 4 KB: proxies commonly limit headers to 8 KiB, and Basic
encoding adds a third.

Clients that only support HTTP Basic, such as Grafana datasources or some
Fluent Bit outputs, send the tenant as the username and the token or ingest key
as the password. The username must equal the `tenant` claim.

## Authorization

- The credential's tenant is the request's tenant. When a request has no
  `X-Scope-OrgID`, Pulse uses the claim. When it has one, the header must match,
  or the request is refused with `403`. The same applies to the `tenant`
  argument of MCP tools.
- Ingest routes need the `ingest` scope. Query routes and MCP query tools need
  `read`. Alerting uses the `alert:*` scopes as its capabilities.
- Credentials never span tenants. Customers who need isolation between
  projects or environments get separate tenants.

## Expiry and outages

- An access token that expired less than `expired_grace_seconds` ago, and is
  otherwise valid, gets a retryable `503` with `Retry-After` on ingest routes
  (gRPC `UNAVAILABLE`). Collectors keep the batch and retry once they hold a
  refreshed token. Nothing is ingested with the expired token.
- On query routes and MCP, an expired token gets `401`, so clients refresh it.
- Keys stay usable for `key_retention_seconds` after the last successful fetch.
  An instance that starts while the issuer is down loads keys and status from
  the bucket mirror.
- A token signed with an unknown `kid` triggers one refresh (at most every
  30 seconds per instance) before it is rejected. Issuers should still publish
  a new key at least one refresh interval before signing with it.
- Each instance remembers validly signed credentials for up to one hour (and
  never past the token's grace window), for at most 10,000 credentials, so
  repeated requests skip the signature check. Claims, expiry, the status list
  and the signing key's presence in the current key set are still checked on
  every request, so removing a key or revoking a credential takes effect as
  soon as the instance refreshes.

## Status list

The status list is a compact JWS with `typ: pulse-status+jwt`, signed with
the same keys. Its claims:

| Claim | Meaning |
| --- | --- |
| `iss`, `aud` | As for tokens. |
| `version` | Integer that never decreases. Pulse ignores a document older than the one it holds, so a replayed document cannot undo revocations. |
| `iat`, `exp` | A new document that has already expired is not applied. A held document stays in force past its `exp`, and Pulse logs every failed refresh. |
| `revoked_kids` | Key IDs that no longer verify anything. Use it for emergency key removal. |
| `revoked_credentials` | `jti` values of revoked ingest keys or tokens. Drop entries once the credential's own `exp` has passed. |
| `suspended_tenants` | Tenants whose credentials get `403`. Their alert rules stop evaluating and notifying. |
| `revoked_before` | Object mapping tenant to a Unix time. Credentials issued before it are rejected. |
| `sentry_projects` | Sentry projects in the [error tracking](error-tracking.md) format, keyed by project ID, at most 100,000. Projects configured in `PULSE_SENTRY_PROJECTS_JSON` take precedence for the same ID. |
| `quotas` | Object mapping tenant to `{"ingest_bytes_per_second": n}`. |

Changes take effect within one refresh interval on every instance. The
document may be up to 16 MiB.

## Quotas

Each instance admits `ingest_bytes_per_second × 10 ÷ live instances` per tenant
in each ten-second window. Bytes are the request's `Content-Length`; requests
without one are charged 4 MiB. Requests over the share get `429` with
`Retry-After: 10` (gRPC `RESOURCE_EXHAUSTED` with retry info). Sentry
ingestion is charged the size of the event body.

Live instances are counted without clustering. While the status list publishes
any quota and Pulse uses object storage, each instance writes an empty
heartbeat object, `auth/members/<instance>/<unix seconds>`, every refresh
interval and lists `auth/members/` to count instances whose latest heartbeat is
at most three intervals old. Each instance removes its previous heartbeat and,
up to 100 per pass, heartbeats older than ten intervals. Clustered nodes count
too; Pulse uses the larger of the two counts.

That costs each instance one PUT, one DELETE and one LIST per refresh interval
(LIST pages grow with the instance count), and needs list and delete permission
on `auth/members/`. Deployments that publish no quotas make none of these
requests.

The division is approximate. An instance that just started or stopped changes
the count within three intervals, and traffic that is unevenly spread across
instances is admitted per instance. Counters are per instance and reset each
window. This is admission control, not metering for billing. Also rate-limit
public ingest keys at your edge.

## MCP authorization

With an issuer configured, `POST /mcp` requires a credential at the HTTP layer:

- No credential gets `401` with
  `WWW-Authenticate: Bearer resource_metadata="<audience>/.well-known/oauth-protected-resource/mcp", scope="read"`.
- An invalid issuer credential adds `error="invalid_token"`.
- A credential with neither `read` nor any `alert:*` scope gets `403` with
  `error="insufficient_scope"`.

`GET /.well-known/oauth-protected-resource` and
`GET /.well-known/oauth-protected-resource/mcp` serve OAuth 2.0 Protected
Resource Metadata (RFC 9728), naming `issuer` as the authorization server.
MCP clients that support OAuth discover the issuer there and request tokens
with `resource=<audience>/mcp` (RFC 8707).

Requests carrying a tenant token or workload identity token keep working as
before.

## Before the body is read

Credentials are checked from headers before Pulse reads a request body:

- OTLP/HTTP exports are authorized before JSON decoding.
- Sentry requests whose key is in a header or the `sentry_key` query parameter
  are authorized before reading. Only a DSN carried inside the envelope still
  needs the body first.
- OTLP/gRPC calls are admitted from their metadata before the listener reads
  or decompresses the message.
- Multipart bodies are no longer parsed on any route.

## Upgrading

The issuer verifier is additive and needs no storage change. The OTLP/gRPC
listener's native interface changed to admit calls before reading them, so
deploy the application with its matching native artifacts. Before issuing
credentials for a deployment, configure every instance with the same
`PULSE_ISSUER_JSON`: an instance without it rejects issuer
credentials as unknown tokens. To stop using tenant tokens, remove
`PULSE_TENANT_TOKENS` once every client uses issuer credentials.

## Client setup

- **OpenTelemetry Collector, Grafana Alloy, Prometheus:** fetch access tokens
  with their OAuth2 auth (`oauth2client`, `otelcol.auth.oauth2`, remote_write
  `oauth2`). Use the issuer's token endpoint as `token_url`, preferably with
  the `urn:ietf:params:oauth:grant-type:jwt-bearer` grant so no shared secret
  exists. Alternatively, read a token file that something else keeps fresh:
  `bearertokenauth` `filename`, or remote_write `authorization.credentials_file`.
- **Clients that only send static headers** (Vector, Fluentd, Logstash, OTel
  SDKs configured through environment variables): use an ingest key, or put a
  Collector in front of them.
- **Sentry SDKs:** use the DSN of a project published in the status list.
- **Grafana datasources:** use Forward OAuth Identity with Grafana signing in
  through the issuer, so each user's own short-lived token reaches Pulse.
- **MCP clients:** point them at `<audience>/mcp` and sign in through OAuth
  discovery.
