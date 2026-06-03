# JIT Elevation Audit Runbook

How to reconstruct, after the fact, what happened during a Tailscale just-in-time elevation. Four independent audit trails carry the same elevation; pulling them all gives a complete forensic picture.

The bot only runs on production and only writes the production tailnet ACL, so this is the cluster + tailnet you should be looking at.

## What you need to know upfront

- **Elevation ID**: the integer primary key of the `tailscale_jit_elevations` row. Surfaced in the Slack approval thread once the bot grants the request, and is the only stable join key across the four trails.
- **Time window**: `expires_at` minus `ttl_seconds` on the row gives the live window. Anything the requester did via the operator proxy during that window inherited the elevated tier.
- **Identities**: `requester_email` on the row is the tailnet identity used for impersonation. Slack ids on the request row are the originals from the slash-command and approve-button events.

## Trail 1: Slack thread

The `tailscale_jit_requests` row's `slack_channel_id` + `slack_message_ts` resolves to the original approval card. The card has been updated through the lifecycle: requester, intent, who approved, when, and whether the elevation completed cleanly or was revoked.

Slack messages are off-platform and Slack-owned, so the thread is the strongest tamper-resistant record we have.

```sql
SELECT requester_slack_id, approver_slack_id, slack_channel_id, slack_message_ts, intent
FROM tailscale_jit_requests
WHERE id = (SELECT request_id FROM tailscale_jit_elevations WHERE id = $ELEVATION_ID);
```

Use the channel id + message ts to deep-link in Slack: `https://tuist.slack.com/archives/<channel_id>/p<ts_without_dot>`.

## Trail 2: Bot's Postgres tables

`tailscale_jit_requests` plus `tailscale_jit_elevations` together describe the full lifecycle the bot drove. Both tables are in the main Tuist Postgres, scoped to the production database.

```sql
SELECT r.id        AS request_id,
       r.requester_email,
       r.target_group,
       r.intent,
       r.status    AS request_status,
       r.approver_email,
       r.approved_at,
       r.denied_at,
       r.failure_reason,
       e.id        AS elevation_id,
       e.status    AS elevation_status,
       e.expires_at,
       e.reverted_at,
       e.revert_failure_reason
FROM tailscale_jit_requests r
LEFT JOIN tailscale_jit_elevations e ON e.request_id = r.id
WHERE e.id = $ELEVATION_ID OR r.id = $REQUEST_ID;
```

State transitions on these rows are always written before the side effect they describe, so a row's status reflects what the bot believed it had done. A mismatch between this and trails 3 / 4 is the signal that drift reconciliation matters.

## Trail 3: Tailscale ACL audit log

Tailscale's admin console keeps an append-only audit of policy file changes. Filter by the OAuth client the bot uses (`tag:tuist-k8s-prod-jit` or whatever the bot's client is tagged) and the timestamp window from trail 2. Each entry shows the whole-document diff; the relevant diff is the `groups.group:tuist-<env>-write` array change.

Out-of-band manual edits in the console also appear here, distinguishable by a non-bot user as the actor. The drift reconciler running in production reaps any unbacked members within five minutes; the entry it leaves shows up here too.

## Trail 4: Operator proxy access log

The Tailscale Kubernetes operator's API server proxy emits one structured log line per forwarded kubectl call: time, tailnet email of the caller, HTTP method, path, response code. Logs are scraped by the `k8s-monitoring` chart into Grafana Cloud Loki.

This is the only per-action record. For the elevation window:

```logql
{namespace="tailscale-operator", pod=~"operator-.*"}
| json
| user="<requester_email>"
| __timestamp__ >= <elevation.approved_at>
| __timestamp__ <  <elevation.expires_at_or_reverted_at>
```

Compare the actual calls against the `intent` field captured at request time. Significant divergence (e.g. the intent said "restart deploy/tuist-tuist-server" and the logs show `DELETE` on unrelated namespaces) is the post-hoc signal worth flagging.

## When something looks wrong

| Symptom | What it means | First thing to check |
|---|---|---|
| Elevation row `status=active` but `expires_at` in the past | RevertWorker missed; drift reconciler should have caught it within 5 min | Trail 3 (was the member ever actually removed?). If yes, the row is just stale; if no, file a ticket. |
| Elevation row `status=reverted` but Tailscale ACL still lists the member | Revert succeeded against an older ACL revision, member was re-added afterwards | Trail 3 for the post-revert add. Run `Tuist.TailscaleJIT.Workers.DriftReconcilerWorker.new(%{}) |> Oban.insert/1` to force an immediate reap. |
| Operator proxy shows kubectl calls outside the elevation window | Either tier-default access (view) was used (expected), OR the requester's identity has a non-bot-managed binding | Confirm requested calls are within `view` scope; if not, the binding was added out-of-band. |
| Slack thread shows approved, no Elevation row exists | ACL POST succeeded but the Elevation insert lost the race (bot crashed in the window) | Trail 3 for the add; if present, file a ticket and reap the orphan via the drift reconciler. |

## How to revoke an active elevation right now

The Revoke button in the Slack thread is the path of first resort. If the bot is unavailable:

```bash
# As an admin with the operator-managed kubeconfig:
kubectl exec deploy/tuist-tuist-server -n tuist -- \
  bin/tuist remote -- 'Tuist.TailscaleJIT.Workers.RevertWorker.new(%{elevation_id: <ID>}) |> Oban.insert()'
```

If even that is unavailable (Postgres down, app down), edit the tailnet ACL in the admin console directly and remove the member from the break-glass group. The next drift reconciler tick will not re-add them, because the matching Elevation row's `status=active` will get re-conciled to `reverted` on the next sweep.

## Related

- `lib/tuist/tailscale_jit/` — implementation tree.
- `infra/tailscale/acls.json` — source-of-truth policy file (mirror into the admin console after edits).
- `infra/helm/tailscale-operator/` — operator wrapper chart that exposes the API server proxy each call goes through.
