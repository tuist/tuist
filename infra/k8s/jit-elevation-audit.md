# JIT Elevation Audit Runbook

How to reconstruct, after the fact, what happened during a JIT elevation. Three independent audit trails carry the same elevation; pulling them all gives the complete forensic picture.

After the Pomerium pivot, `tuist-ops` (mgmt cluster) owns the bot's tables and serves the Pomerium ext_authz endpoint; the tailnet ACL is no longer mutated at runtime, so the historical "Tailscale ACL audit log" trail no longer applies.

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

This is the per-action trail. Pomerium emits one structured log line per kubectl HTTP call it proxies, including the authenticated user's email, the verb + resource the call targeted, and the response code from the apiserver. Shipped to Grafana Cloud Loki via k8s-monitoring.

```logql
{cluster=~"tuist-k8s-production|tuist-k8s-canary|tuist-k8s-staging",
 app_kubernetes_io_name="pomerium"}
  | json
  | user_email = "marek@tuist.dev"
  | timestamp >= "<elevation expires_at - ttl_seconds>"
  | timestamp <= "<elevation expires_at>"
```

Tighten with `method`, `path`, or `response_status` to find the specific calls a forensics request is about (e.g. `method="DELETE"` to list everything the user destroyed during the window).

If apiserver audit logging is enabled (see the follow-up in the PR description), join on the apiserver's per-resource audit events for full request/response bodies. Pomerium's log gives you "what URL and what response code"; apiserver audit gives you "what the request body looked like."

## What stopped being a trail

The pre-pivot design had a fourth trail: the **Tailscale ACL audit log** (every ACL diff Tailscale recorded as the bot rewrote `acls.json` to add/remove break-glass members). That trail no longer exists — `acls.json` is a static document edited only through code review, and there are no runtime ACL mutations to record. If you're looking at a pre-pivot incident, the old trail is in the Tailscale admin console's Audit log; for any post-pivot incident, Pomerium's per-call log is the per-action trail.
