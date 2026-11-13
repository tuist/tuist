# Staging GreptimeDB Grafana

Standalone, private Grafana qualification of upstream GreptimeDB. This is not a
fork, rename, production cutover, or replacement of Grafana Cloud alerts/sources.
A future Pulse fork remains a separate decision after qualification.

The dedicated upstream plugin supports SQL logs and trace waterfalls but is
unsigned and cannot run on Grafana Cloud. This chart pins v3.0.4 and verifies the
release archive SHA256 before installing it into this Grafana only. A separate
built-in Prometheus source queries `/v1/prometheus`. Both sources authenticate as
the read-only `dashboard` user, database `public`.

## Prerequisites and deployment

Deploy only to staging, namespace `observability`, after GreptimeDB's ESO-backed
dashboard identity and ingestion gateway have been qualified. ESO
reads the staging store's existing `PULSE_TOKEN/password` directly into a dedicated
Secret. Neither Helm nor an agent needs its value. The environment interpolation
uses `$GREPTIME_DASHBOARD_PASSWORD`, not `${...}`, to preserve literal dollar
signs in a password. Token changes require a coordinated Grafana/backend rollout;
there is no agent-driven rotation or Secret read.

The parent deployment workflow should run:

```sh
helm upgrade --install greptime-grafana-staging infra/helm/greptimedb-grafana \
  --namespace observability --wait --timeout 5m
```

No public Ingress, Funnel, load balancer, or anonymous Grafana login is created.
Tailscale Ingress serves `https://greptime-grafana-staging.taild6d7bb.ts.net` to
authorized tailnet users. Tailscale Serve strips incoming identity headers and
injects `Tailscale-User-Login`; Grafana's auth proxy creates Viewer accounts only.
A NetworkPolicy admits port 3000 only from this Ingress's operator-managed proxy
pod in `tailscale-operator`, not other pods or tailnet clients. Verify the live
proxy labels match the policy before declaring the identity boundary working.
Existing tailnet ACLs govern who may reach the device; no ACL change is included.
Do not enable Funnel or share this device with external users.

The local SQLite database is disposable. Datasources and the four-panel home
dashboard are provisioned from source; no saved operator dashboards or alerts
are stored here. Viewer exploration is enabled, but dashboard saving, source
editing, and admin/password login are not. No ServiceAccount token is mounted.

## Checks

Run `python3 infra/helm/greptimedb-grafana/test_chart.py` (Helm and PyYAML required).
This checks rendering and the staging, secret-reference, network and datasource
contracts. It does not prove live networking or plugin queries.

Run the read-only live check from an authorized tailnet device:

```sh
python3 infra/helm/greptimedb-grafana/check_live.py \
  https://greptime-grafana-staging.taild6d7bb.ts.net
```

It requires nonempty metrics, logs and spans within the last 15 minutes and
checks both authenticated sources, Viewer role and trace waterfall fields.
Local synthetic verification against real Grafana and GreptimeDB qualifies
queries and rendering only, not live staging ingestion or the Tailscale identity boundary.

After deployment, verify all of these through the actual tailnet URL:

- No injected identity: unauthenticated API requests are rejected.
- Authenticated user is Viewer, never Admin; source settings remain non-editable.
- Both `/api/datasources/uid/<uid>/health` checks pass.
- `greptime-staging-metrics`: a real `up` instant/range query returns samples.
- `greptime-staging-sql`: bounded real log and span queries return frames; trace
  waterfall returns the selected trace, timestamps and measured duration.
- A harmless CREATE attempt through this datasource is rejected by Greptime's
  read-only identity. If it succeeds, stop qualification; do not widen access.
- The home dashboard renders metrics, logs, recent spans and selected trace;
  reload it and check that data is still queried, not a cached picture.
- Existing Grafana Cloud source/alert configuration remains unchanged.

Empty frames or a healthy `/api/health` alone are not proof of integration.
Inspect actual query errors, frame schemas and returned sample identities.
