# JIT Elevation Audit Runbook

How to reconstruct, after the fact, what happened during a JIT elevation. Three independent audit trails carry the same elevation; pulling them all gives the complete forensic picture.

After the Pomerium pivot, `tuist-ops` (mgmt cluster) owns the bot's tables and serves the Pomerium impersonation policy endpoint; the tailnet ACL is no longer mutated at runtime, so the historical "Tailscale ACL audit log" trail no longer applies.

**Staging is not part of this runbook.** Its `tuist-staging-write` group is standing access for every engineering identity, so a staging mutation has no elevation row, no Slack card and no TTL to reconstruct — only the Pomerium access log (trail 3), which still carries the email, verb and path of every request. Staging's Pulse has no SQL source, though, so that log currently has no read path (see trail 3). Elevations exist for canary and production only.

## What you need to know upfront

- **Elevation ID**: the integer primary key of the `tailscale_jit_elevations` row in tuist-ops's database. Surfaced in the Slack approval thread once the bot grants the request, and is the stable join key across trails.
- **Time window**: `expires_at` minus `ttl_seconds` on the row gives the live window. Anything the requester did via Pomerium during that window inherited the elevated impersonation.
- **Identities**: `requester_email` on the row is the Google Workspace / tailnet identity Pomerium authenticated. Slack ids on the request row are the originals from the slash-command and approve-button events.

## Trail 1: Slack thread

The `tailscale_jit_requests` row's `slack_channel_id` + `slack_message_ts` resolves to the original approval card. The card has been updated through the lifecycle: requester, intent, who approved, when, and whether the elevation completed cleanly or was revoked.

Slack messages are off-platform and Slack-owned — the strongest tamper-resistant record we have.

```sql
-- run on tuist-ops's Postgres (mgmt cluster):
--   kubectl exec -n tuist-ops -c postgres <tuist-ops-pg-cluster-pod> -- psql
SELECT requester_slack_id, approver_slack_id, slack_channel_id, slack_message_ts, intent
FROM tailscale_jit_requests
WHERE id = (SELECT request_id FROM tailscale_jit_elevations WHERE id = $ELEVATION_ID);
```

Deep-link: `https://tuist.slack.com/archives/<channel_id>/p<ts_without_dot>`.

## Trail 2: tuist-ops Postgres

`tailscale_jit_requests` plus `tailscale_jit_elevations` together describe the full lifecycle the bot drove. Both tables live in the **tuist-ops** CNPG cluster in mgmt, NOT in the main Tuist server's database.

```sql
SELECT r.id          AS request_id,
       r.requester_email,
       r.target_group,
       r.intent,
       r.status      AS request_status,
       r.approver_email,
       r.approved_at,
       r.denied_at,
       r.failure_reason,
       e.id          AS elevation_id,
       e.status      AS elevation_status,
       e.expires_at,
       e.reverted_at,
       e.revert_failure_reason
FROM tailscale_jit_requests r
LEFT JOIN tailscale_jit_elevations e ON e.request_id = r.id
WHERE e.id = $ELEVATION_ID;
```

## Trail 3: Pomerium access log (per-call kubectl audit)

This is the per-action trail. Pomerium emits one structured JSON line per kubectl HTTP call it authorizes (`authorize check`), with the authenticated user's `email`, the `method` and `path` of the call, the API `host`, and whether it was allowed (`allow`). k8s-monitoring ships it to the cluster's Pulse, where it is a row of `opentelemetry_logs`: the Loki labels are in the `resource_attributes` JSON and the line is in `body`.

Read it from Grafana through the **Tuist Pulse SQL** data source (`pulse-sql`): open Explore, switch the query to Code and the format to Table. Only production's Pulse serves SQL, so this covers production elevations only. **Canary elevations currently have no per-call trail:** canary's (and staging's) Pomerium lines are stored in that cluster's Pulse, which has no SQL source and serves no Loki query API, so trails 1 and 2 are all a canary elevation has until one is added. Replace `<email>` with `requester_email` and `<start>` / `<end>` with the elevation window as UTC timestamps (`expires_at` minus `ttl_seconds`, then `expires_at`):

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
  AND json_get_string(parse_json(body), 'email') = '<email>'
ORDER BY timestamp
```

This follows the privileged-access query in [`infra/log-review.md`](../log-review.md), which explains the `host` filter. Tighten it to the calls a forensics request is about, for example `AND regexp_like(body, '"method":"DELETE"')` to list everything the user destroyed during the window, or `AND NOT regexp_like(body, '"path":"[^"]*selfsubject')` to drop `kubectl auth whoami` and `kubectl auth can-i`. A denied call (`allow` false) is an attempt the policy blocked, which is worth reading rather than filtering out.

Where the API server audit log is enabled ([credential-rotation.md → API server audit log](../credential-rotation.md#api-server-audit-log)), it records Secret reads and ServiceAccount token requests at Metadata level, including those made by ServiceAccounts and nodes that never pass Pomerium. It records no request or response bodies, and nothing for other resources.

## What stopped being a trail

The pre-pivot design had a fourth trail: the **Tailscale ACL audit log** (every ACL diff Tailscale recorded as the bot rewrote `acls.json` to add/remove break-glass members). That trail no longer exists — `acls.json` is a static document edited only through code review, and there are no runtime ACL mutations to record. If you're looking at a pre-pivot incident, the old trail is in the Tailscale admin console's Audit log; for any post-pivot incident, Pomerium's per-call log is the per-action trail.
