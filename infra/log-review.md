# Log review runbook

The queries behind the periodic log review required by the
[Logging and monitoring policy](https://handbook.tuist.io/security/secure-development-and-operations/logging-and-monitoring-policy).

A review is not reading logs. It is running these queries and reconciling each
against an independent record. The finding is whatever appears in one source
and not the other.

**Retention is thirty days.** A review that slips cannot be performed
retrospectively, so the monthly review has to land in the first week of the
period it covers.

These queries were validated against production data on 19 August 2026 over a
thirty day window. The server writes Logger metadata as `key=value` pairs after
a bare timestamp, and `logfmt` parses that cleanly despite the timestamp.
Pomerium writes JSON, so its queries use `json` and its field names are
hyphenated in the source (`allow-why-true` and the like), which the parser
exposes with underscores.

## 1. Privileged cluster access without an approved elevation

The strongest query available to us, because the elevation record is
authoritative rather than inferred. Read access is allowed to everyone by
design, so only mutating calls are in scope.

**From Loki**, the calls:

```logql
{cluster="tuist-production", namespace="pomerium"}
  |= "authorize check"
  | json
  | host = "kube-prod.tuist.dev"
  | method =~ "POST|PUT|PATCH|DELETE"
  | path !~ ".*selfsubject.*"
  | line_format "{{.email}} {{.method}} {{.path}} allow={{.allow}}"
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

**From Loki**, the accesses:

```logql
{cluster="tuist-production", namespace="tuist"}
  |= "operator_grant_jti"
  | logfmt
  | line_format "{{.operator_grant_sub}} {{.operator_grant_jti}} {{.selected_account_handle}} {{.request_path}} {{.status}}"
```

The server does not emit a `route` field on every record, so the path is
`request_path`.

**From the tuist-ops database**, the grants that were issued and why.

**A finding is** a grant identifier appearing in the logs with no matching
issued grant, which would mean a forged or replayed grant, or a grant whose
recorded justification does not match what was actually accessed.

## 3. Authentication failures

```logql
sum by (client_address, auth_outcome) (
  count_over_time(
    {cluster="tuist-production", namespace="tuist"}
      |= "authentication attempt"
      | logfmt
      | auth_outcome != "success"
      [1h]
  )
)
```

Do not try to infer the outcome from the response status. Every result of a
sign-in attempt redirects, a wrong password just as much as a success, so the
status cannot separate them and a `4..` filter matches neither. The controller
emits an explicit `auth_outcome` of `success`, `invalid_credentials`,
`rate_limited` or `unconfirmed`, and that is the field to count.

Group by `client_address` rather than by account. A failed sign-in has no
authenticated account, so `auth_account_handle` is empty on exactly the records
this query is about.

**A finding is** anything sustained from one address. A handful of failures is
someone mistyping a password.

## 4. Loss of log ingestion

Visibility loss looks identical to quiet, so this is what makes the other
three trustworthy.

```logql
sum by (namespace) (
  count_over_time({cluster="tuist-production"}[1h])
)
```

**A finding is** any namespace that goes to zero and stays there while the
workload is still running. Worth promoting to an alert once the baseline shape
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
through Loki. They are not part of the monthly pass.
