# Log review runbook

The queries behind the periodic log review required by the
[Logging and monitoring policy](https://handbook.tuist.io/security/secure-development-and-operations/logging-and-monitoring-policy).

A review is not reading logs. It is running these queries and reconciling each
against an independent record. The finding is whatever appears in one source
and not the other.

The logs are in production's Pulse, read from Grafana through the **Tuist
Pulse SQL** data source (`pulse-sql`): open Explore, switch the query to Code
and the format to Table. Every line is a row of `opentelemetry_logs`, with the
Loki labels (`cluster`, `namespace`, `service_name`) in the
`resource_attributes` JSON and the line itself in `body`. Replace `<start>` and
`<end>` with the period under review as UTC timestamps, such as
`2026-12-01T00:00:00Z` (the queries already quote them). A day of the server's
logs takes about a minute to scan, so if Grafana times out on a longer period,
run the query a day at a time.

Production's Pulse sets no expiry on these logs (its `public` database has
`ttl = 'forever'`), but that is not a retention guarantee. It holds nothing
before 14 November 2026 23:00 UTC, when Pulse was reset during its rename, and a
reset (`pulse-deployment.yml`'s `reset` input) or a storage layout change
deletes everything again. Keep each review's results in its record rather than
counting on being able to re-run the queries later, and land the monthly review
in the first week of the period it covers. Grafana Cloud Loki kept thirty days
and is being retired; the LogQL versions of these queries are in this file's
history.

The server writes Logger metadata as `key=value` pairs after a bare timestamp,
so its queries take each field from the line with `regexp_match`. Pomerium
writes JSON, so its query reads fields with `parse_json`, using the source's
names (`allow-why-true` and the like are hyphenated). The LogQL versions were
validated against production data on 19 August 2026 over a thirty day window,
and these SQL versions against Pulse on 17 November 2026.

## 1. Privileged cluster access without an approved elevation

The strongest query available to us, because the elevation record is
authoritative rather than inferred. Read access is allowed to everyone by
design, so only mutating calls are in scope.

**From Pulse**, the calls:

```sql
SELECT timestamp,
  json_get_string(parse_json(body), 'email') AS email,
  json_get_string(parse_json(body), 'method') AS method,
  json_get_string(parse_json(body), 'path') AS path,
  json_get_bool(parse_json(body), 'allow') AS allow
FROM opentelemetry_logs
WHERE timestamp >= '<start>' AND timestamp < '<end>'
  AND json_get_string(resource_attributes, 'cluster') = 'tuist-production'
  AND json_get_string(resource_attributes, 'namespace') = 'pomerium'
  AND body LIKE '%authorize check%'
  AND body LIKE '%"host":"kube-prod.tuist.dev"%'
  AND regexp_like(body, '"method":"(POST|PUT|PATCH|DELETE)"')
  AND NOT regexp_like(body, '"path":"[^"]*selfsubject')
ORDER BY timestamp
```

Three filters here were learned the hard way and should not be dropped. Without
the `host` filter the results are dominated by the operations app's own webhook
traffic, which is not cluster access at all. Without the `selfsubject` filter
you get `kubectl auth whoami` and `kubectl auth can-i`, which are POSTs that
mutate nothing. And `allow` is worth reading rather than filtering on: a denied
mutating call is an attempted write without elevation, which is its own finding
even though the control worked.

**From the tuist-ops database**, the windows they should fall inside:

```sql
select user_email, granted_at, expires_at, env, intent
from tailscale_jit_elevations
where granted_at >= now() - interval '30 days'
order by granted_at;
```

**A finding is** a mutating call whose timestamp falls outside every elevation
window for that user. Expect a benign population the first time: confirm each
one is genuinely a read the access model permits, and if the query keeps
surfacing the same shape, narrow it here rather than dismissing it monthly.

## 2. Operator access to customer data

Every request made under an operator grant carries the grant identifier, so
this reconciles the log against the grants that were actually issued.

**From Pulse**, the accesses:

```sql
SELECT timestamp,
  regexp_match(body, '(?:^| )operator_grant_sub=([^ ]*)')[1] AS operator_grant_sub,
  regexp_match(body, '(?:^| )operator_grant_jti=([^ ]*)')[1] AS operator_grant_jti,
  regexp_match(body, '(?:^| )selected_account_handle=([^ ]*)')[1] AS selected_account_handle,
  regexp_match(body, '(?:^| )request_path=([^ ]*)')[1] AS request_path,
  regexp_match(body, '(?:^| )live_view=([^ ]*)')[1] AS live_view,
  regexp_match(body, '(?:^| )status=([^ ]*)')[1] AS status
FROM opentelemetry_logs
WHERE timestamp >= '<start>' AND timestamp < '<end>'
  AND json_get_string(resource_attributes, 'cluster') = 'tuist-production'
  AND json_get_string(resource_attributes, 'namespace') = 'tuist'
  AND body LIKE '%operator_grant_jti%'
ORDER BY timestamp
```

The server does not emit a `route` field on every record, so the path is
`request_path`.

**Reads through Atlas without a grant.** Operators calling the MCP server
through Atlas can read any customer account without a grant. Those requests
carry `atlas_operator_email` on the request line, and
`atlas_operator_read_account_id` on the ones that used operator access. The
server's logs arrive as console lines, so the fields are parsed from the line
rather than filtered as attributes:

```sql
SELECT timestamp,
  regexp_match(body, '(?:^| )atlas_operator_email=([^ ]*)')[1] AS atlas_operator_email,
  regexp_match(body, '(?:^| )atlas_operator_read_account_id=([^ ]*)')[1] AS atlas_operator_read_account_id,
  regexp_match(body, '(?:^| )request_path=([^ ]*)')[1] AS request_path,
  regexp_match(body, '(?:^| )status=([^ ]*)')[1] AS status
FROM opentelemetry_logs
WHERE timestamp >= '<start>' AND timestamp < '<end>'
  AND json_get_string(resource_attributes, 'cluster') = 'tuist-production'
  AND json_get_string(resource_attributes, 'namespace') = 'tuist'
  AND body LIKE '%atlas_operator_read_account_id%'
ORDER BY timestamp
```

Successful request lines are otherwise sampled at 10% by the log collector
(`infra/helm/k8s-monitoring/values.yaml`). Lines carrying
`atlas_operator_read_account_id` or `operator_grant_jti` are exempt, so both
queries in this section see every such line written after that exemption
shipped; earlier records are sampled. Dashboard pages are LiveViews, and moving
between them happens over the LiveView socket without an HTTP request, so each
page an operator opens under a grant is also recorded as an `Operator grant
page view` line carrying `operator_grant_jti` and `live_view`, which the grant
query picks up. Interactions within a page (filters, tabs, pagination) are not
recorded individually.

Atlas records the tool and arguments of each of these calls as
`mcp.tool_called` in its audit log, so the two should agree. They are not
guaranteed to: the server trusts any request carrying Atlas' ServiceAccount
token, so someone holding that token and an operator's OAuth token could call
the server directly and skip Atlas' audit. That token also authenticates the
internal Atlas database API. This reconciliation is how such use is found.

**From the tuist-ops database**, the grants that were issued and why.

**A finding is** a grant identifier appearing in the logs with no matching
issued grant, which would mean a forged or replayed grant, or a grant whose
recorded justification does not match what was actually accessed. For reads through Atlas, a finding is an operator read in the server logs
with no matching `mcp.tool_called` row in Atlas.

## 3. Authentication failures

```sql
SELECT regexp_match(body, '(?:^| )client_address=([^ ]*)')[1] AS client_address,
  regexp_match(body, '(?:^| )auth_outcome=([^ ]*)')[1] AS auth_outcome,
  count(*) AS attempts,
  count(DISTINCT date_trunc('hour', timestamp)) AS hours_with_attempts,
  min(timestamp) AS first_attempt,
  max(timestamp) AS last_attempt
FROM opentelemetry_logs
WHERE timestamp >= '<start>' AND timestamp < '<end>'
  AND json_get_string(resource_attributes, 'cluster') = 'tuist-production'
  AND json_get_string(resource_attributes, 'namespace') = 'tuist'
  AND body LIKE '%authentication attempt%'
  AND body NOT LIKE '%auth_outcome=success%'
GROUP BY client_address, auth_outcome
ORDER BY hours_with_attempts DESC, attempts DESC
```

Sorting by the hours an address failed in, not by its busiest hour, puts a slow
attempt spread over days (a few an hour from one address) at the top instead of
among single mistyped passwords.

Do not try to infer the outcome from the response status. Every result of a
sign-in attempt redirects, a wrong password just as much as a success, so the
status cannot separate them and a `4..` filter matches neither. The controller
emits an explicit `auth_outcome` of `success`, `invalid_credentials`,
`rate_limited`, `unconfirmed` or `turnstile_failed`, and that is the field to
count.

Group by `client_address` rather than by account. A failed sign-in has no
authenticated account, so `auth_account_handle` is empty on exactly the records
this query is about.

**A finding is** anything sustained from one address. A handful of failures is
someone mistyping a password.

## 4. Loss of log ingestion

Visibility loss looks identical to quiet, so this is what makes the other
three trustworthy.

```sql
SELECT json_get_string(resource_attributes, 'namespace') AS namespace,
  min(timestamp) AS first_line,
  max(timestamp) AS last_line,
  count(DISTINCT date_trunc('hour', timestamp)) AS hours_with_lines,
  count(*) AS lines
FROM opentelemetry_logs
WHERE timestamp >= '<start>' AND timestamp < '<end>'
  AND json_get_string(resource_attributes, 'cluster') = 'tuist-production'
GROUP BY namespace
ORDER BY hours_with_lines
```

An hour without lines produces no row in any grouped query, so look for
absence in these columns rather than for zeros: `last_line` well before
`<end>` means a namespace stopped, and `hours_with_lines` below the period's
hour count (24 a day) means it had gaps. To see where a gap falls, rerun with
`date_trunc('hour', timestamp) AS time` added to the select and the grouping,
for one namespace, and switch the format to Time series.

**A finding is** any namespace that stops logging, or goes silent for hours,
while the workload is still running. Worth promoting to an alert once the baseline shape
is known.

## The record

The output of the review, not the logs, is the evidence. Keep it short:

```
Reviewer:
Date:
Period covered:
Sources examined:
Findings and dispositions:
```

A finding is closed with a severity, what was investigated, the conclusion,
and either the action taken or why none was needed. See section 3.2 of the
policy for the severity definitions and their response times.

## Known shape of the data

Measured over the thirty days to 19 August 2026, so the first review knows what
normal looks like before deciding anything is abnormal:

- Mutating cluster calls run to several hundred in a month across three
  engineers, plus a small number of denials from unauthenticated sessions. The
  bulk are job creation and pod subresource calls.
- Operator grant usage is present but low volume.
- Sign-in attempts run a few hundred a month. The split between successes and
  failures has not been measured against `auth_outcome`, because that field
  ships with this runbook; the earlier figures were derived from response
  status, which cannot distinguish the two.

These are baselines, not thresholds. Re-measure rather than trusting them once
the fleet or the team changes.

## Not covered here

Third-party administrative logs (identity provider, source control) are
reviewed quarterly and are read in those providers' own consoles rather than
through Pulse. They are not part of the monthly pass.
