# Log review runbook

The queries behind the periodic log review required by the
[Logging and monitoring policy](https://handbook.tuist.io/security/secure-development-and-operations/logging-and-monitoring-policy).

A review is not reading logs. It is running these queries and reconciling each
against an independent record. The finding is whatever appears in one source
and not the other.

**Retention is thirty days.** A review that slips cannot be performed
retrospectively, so the monthly review has to land in the first week of the
period it covers.

**Before the first run**, open each query in Grafana Explore and confirm the
parser and field names against real data. The server writes Logger metadata
into the log line as `key=value` pairs after the timestamp, so `logfmt` should
work, but the leading timestamp and level may need `pattern` instead. Fix the
queries here once rather than rediscovering it every month.

## 1. Privileged cluster access without an approved elevation

The strongest query available to us, because the elevation record is
authoritative rather than inferred. Read access is allowed to everyone by
design, so only mutating calls are in scope.

**From Loki**, the calls:

```logql
{cluster="tuist-production", namespace="pomerium"}
  | logfmt
  | method =~ "POST|PUT|PATCH|DELETE"
  | path !~ ".*subjectaccessreviews.*"
  | line_format "{{.user_email}} {{.method}} {{.path}} {{.response_code}}"
```

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
  | line_format "{{.operator_grant_sub}} {{.operator_grant_jti}} {{.selected_account_handle}} {{.route}} {{.status}}"
```

**From the tuist-ops database**, the grants that were issued and why.

**A finding is** a grant identifier appearing in the logs with no matching
issued grant, which would mean a forged or replayed grant, or a grant whose
recorded justification does not match what was actually accessed.

## 3. Authentication failures

```logql
sum by (auth_account_handle) (
  count_over_time(
    {cluster="tuist-production", namespace="tuist"}
      | logfmt
      | route = "/users/log_in"
      | status =~ "4.."
      [1h]
  )
)
```

Run it a second time grouped by source address instead of account, to catch a
spray across many accounts rather than a brute force against one.

**A finding is** anything sustained. A handful of failures is someone
mistyping a password.

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

## Not covered here

Third-party administrative logs (identity provider, source control) are
reviewed quarterly and are read in those providers' own consoles rather than
through Loki. They are not part of the monthly pass.
