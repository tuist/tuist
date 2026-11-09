# Grafana rule-by-rule modeling checklist

Generated from `grafana-rule-inventory.json` by `mix run --no-start plans/alerting/validate_inventory.exs --write-matrix`.
All 115 UIDs are included. This is a planning inventory, not a claim of implemented compatibility.
Every row still requires importer round-trip, source binding, numerical/label/error fixtures,
routing fixtures and shadow comparison before its migration status can become approved.
Source query definitions and annotation templates remain in the JSON snapshot.

`main metrics` and `main logs` identify observed Grafana sources, NOT confirmed Pulse-resident inputs.
Every selector producer/residency closure remains a migration blocker until verified; recording consumers must move with their inputs.
`synthetic` identifies externally produced probe/threshold/log inputs and is not implicitly Alloy telemetry.
`usage` requires Grafana's external usage metrics; `SQL` requires an existing external ClickHouse source.
Mixed-source rules must remain mixed-source expression graphs. `policy` means notification-tree routing;
`record` means no alert notification. Blank no-data/error settings belong to recording entries, not default alert policies.

| UID | Rule | Observed sources (residency unverified) | Expression nodes | Cadence / for / keep-firing | Paused | No-data / error | Receiver |
| --- | --- | --- | --- | --- | --- | --- | --- |
| afg7f8blhjmyob | Cache CPU | main metrics | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| ff5dn2b82u3nke | Cache Node Disk Usage Watermark | main metrics | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| cftoutryd1jwge | Kura - 5xx errors on public cache routes | main metrics | threshold | 300s / 5m / 0s | no | OK / Error | policy |
| cfx2v81nrmfpce | Kura - account at its egress ceiling | main metrics | threshold | 300s / 1h / 0s | no | OK / Alerting | policy |
| bfyi8f8z3whkwa | Kura - admission refusing instances | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| dfx20t6sg70u8f | Kura - cache box out of memory | main metrics | threshold | 300s / 15m / 0s | no | OK / Alerting | policy |
| efvvcl6qu3tvkc | Kura - cache pod restart loop | main metrics | threshold | 300s / 10m / 0s | no | OK / Alerting | policy |
| dfvv8qn09k1z4b | Kura - cache reads shed under capacity pressure | main metrics | threshold | 300s / 10m / 0s | no | OK / Error | policy |
| ffvvcpp359qm8d | Kura - cache telemetry missing | main metrics | threshold | 300s / 0s / 0s | no | OK / Alerting | policy |
| efx2uhse2es5cf | Kura - egress budget almost entirely consumed | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| dfx2utleekruoc | Kura - egress budget heavily used | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| afx2w05l6se0wc | Kura - egress shaping integrity | main metrics | threshold | 300s / 15m / 0s | no | Alerting / Alerting | policy |
| bfybzuvqgyzggc | Kura - ingress returning malformed or 502 responses | main logs | threshold | 300s / 15m / 0s | no | OK / Error | policy |
| dfxnedzs40i68f | Kura - instance provisioned but not serving | main metrics | threshold | 300s / 30m / 0s | no | Alerting / Alerting | policy |
| afx2mswafmvi8a | Kura - instance retention horizon under a day | main metrics | threshold | 300s / 1h / 0s | no | OK / Alerting | policy |
| dfygid92hevi8d | Kura - instance retention horizon under a day for three days | main metrics | threshold | 300s / 1h / 0s | no | OK / Alerting | policy |
| dfvvcp2lfgb9cd | Kura - metadata store write buffer saturated | main metrics | threshold | 300s / 10m / 0s | no | OK / OK | policy |
| kura-new-instance-slow | Kura - new instances slow to serve | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| cfx21glh3ufb4b | Kura - pod OOM-killed | main metrics | threshold | 300s / 0s / 0s | no | OK / Alerting | policy |
| afx23ub0nn4zke | Kura - pod living above its memory request | main metrics | threshold | 300s / 1h / 0s | no | OK / Alerting | policy |
| bfx213k5258g0b | Kura - pod under memory pressure | main metrics | threshold | 300s / 10m / 0s | no | OK / Alerting | policy |
| ffx2xchowcwlce | Kura - public request latency high | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| fg05sgfj5u70gb | Kura - receiving no REAPI requests | main metrics | threshold | 300s / 0s / 0s | no | NoData / Alerting | Slack #notifications 2 |
| cfyi8cxo4t4hsc | Kura - region admission cannot take an enterprise instance | main metrics | threshold | 300s / 15m / 0s | no | OK / Alerting | policy |
| cfyi8f0lyqayof | Kura - region admission headroom running out | main metrics | threshold | 300s / 2h / 0s | no | OK / Alerting | policy |
| efx1xqen168zka | Kura - region cannot place another instance | main metrics | threshold | 300s / 15m / 0s | no | OK / Alerting | policy |
| dfx23hmvx0pvke | Kura - region has room for one more instance | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| dfx23oim6hx4wf | Kura - region host memory low | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| ffzpv5re9spa8a | Kura - region replication lagging | main metrics | threshold | 300s / 10m / 0s | no | NoData / Error | policy |
| cfx2wlcj6t81sa | Kura - response streams waiting or degraded | main metrics | threshold | 300s / 10m / 0s | no | OK / Alerting | policy |
| kura-rollout-paused | Kura - rollout paused | main metrics | threshold | 300s / 15m / 0s | no | OK / Error | Slack #notifications 2 |
| kura-rollout-stalled | Kura - rollout running without progress | main metrics | threshold | 300s / 5m / 0s | no | OK / Error | Slack #notifications 2 |
| efwtvv4wuspvkc | Kura - shedding cache writes by kind | main metrics | threshold | 300s / 0s / 0s | no | OK / Alerting | policy |
| efzmp2v9usveob | Kura - shedding remote-execution reads | main metrics | threshold | 300s / 0s / 0s | no | OK / Alerting | policy |
| efx228hqspvk0b | Kura - trickling cache write sheds | main metrics | threshold | 300s / 10m / 0s | no | OK / Alerting | policy |
| efxjihza4os1sc | Kura box cannot take back its largest replica | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| dfxj89n1poidca | Kura instance below its replica count | main metrics | threshold | 300s / 30m / 0s | no | OK / Alerting | policy |
| ffie22iqdd534c | No recorded requests | main metrics | threshold | 300s / 5m / 0s | yes | Alerting / Error | policy |
| efdq33b6ysh6oa | cache-nginx 502 | main logs | reduce, threshold | 300s / 0s / 0s | no | OK / Error | policy |
| ffz1ualjy8fswd | Kura instance has no ready replicas | main metrics | threshold | 60s / 2m / 0s | no | NoData / Error | policy |
| dfybzqdz5rh1cb | Xcode cache - CI remote reads slow for an account | SQL | threshold | 600s / 0s / 30m | no | OK / Error | policy |
| afwtwlzgkderke | Kura - replication outbox approaching its cap | main metrics | threshold | 60s / 0s / 0s | no | OK / Alerting | policy |
| cfx9b821ea328b | ClickHouse backup failed | main metrics | threshold | 60s / 5m / 0s | no | OK / Alerting | policy |
| dfx9baqe4a134f | ClickHouse data disk watermark | main metrics | threshold | 60s / 30m / 0s | no | OK / OK | policy |
| efx9b9ribbqwwa | ClickHouse mirror is losing writes | main metrics | threshold | 60s / 15m / 0s | no | OK / OK | policy |
| dfx9bbn39ff9ca | ClickHouse rows diverging between servers | main metrics | threshold | 60s / 30m / 0s | no | OK / OK | policy |
| efx9b8vfmd2ioc | ClickHouse schema drift between servers | main metrics | threshold | 60s / 15m / 0s | no | OK / OK | policy |
| efx9b65i5o5q8f | In-cluster ClickHouse not ready | main metrics | threshold | 60s / 10m / 0s | no | OK / Alerting | policy |
| efx9b72za31fke | In-cluster ClickHouse replica is read-only | main metrics | threshold | 60s / 5m / 0s | no | OK / Alerting | policy |
| dfsb8jl14lwjkd | Bare-Metal Node Disk Usage Watermark | main metrics | threshold | 60s / 15m / 0s | no | NoData / Error | policy |
| afxcyee4hw1dsd | CAPI - Cluster removed from git but still running | main metrics | threshold | 60s / 15m / 0s | no | OK / OK | policy |
| dfxcybgvsrvggc | CAPI - control plane below desired replicas | main metrics | threshold | 60s / 15m / 0s | no | OK / Alerting | policy |
| cfxcyc9xtvlkwc | CAPI - control-plane telemetry missing from the management cluster | main metrics | threshold | 60s / 15m / 0s | no | OK / OK | policy |
| afxcyafkxuzgga | CAPI - etcd has no leader | main metrics | threshold | 60s / 2m / 0s | no | OK / Alerting | policy |
| cfxcydivbi4u8d | CAPI - orphan Hetzner server with no owning Machine | main metrics | threshold | 60s / 15m / 0s | no | OK / OK | policy |
| dfxcyfac3943kd | CAPI - reconciliation checks have stopped running | main metrics | threshold | 60s / 0s / 0s | no | OK / Alerting | policy |
| efxczczr9xlhcd | CAPI - reconciliation telemetry absent entirely | main metrics | threshold | 60s / 0s / 0s | no | OK / Alerting | policy |
| dfxdeuqc1hn28d | Flux - reconciliation has stalled fleet-wide | main metrics | threshold | 60s / 10m / 0s | no | OK / Alerting | policy |
| efxdevi9ry5mob | Flux - telemetry missing from the management cluster | main metrics | threshold | 60s / 15m / 0s | no | OK / Alerting | policy |
| eg0ao1eoesjk0d | Metrics samples rejected as duplicate timestamps | usage | threshold | 60s / 1h / 0s | no | OK / OK | policy |
| ffvn55h51mz28d | Pod Cannot Be Scheduled | main metrics | threshold | 60s / 30m / 0s | no | OK / OK | policy |
| efsvikd2rq22oa | Pod restarts (possible overload) | main metrics | threshold | 60s / 1m / 0s | no | OK / Error | policy |
| efz3meilw8xkwb | Tailscale Proxy Has No Ready Replica | main metrics | threshold | 60s / 30m / 0s | no | OK / OK | policy |
| fft9axi4o7y0we | Tuist Server - Available Replicas Below Spec | main metrics | math, threshold | 60s / 5m / 0s | no | NoData / Error | Incidents |
| ffx86ycdq1urkb | kura:node_pool | main metrics | source condition | 60s / 0s / 0s | no | - / - | record |
| bfx1veuysqhogf | kura:node_region | main metrics | source condition | 60s / 0s / 0s | no | - / - | record |
| dfx1v9sonabk0f | kura:pod_region | main metrics | source condition | 60s / 0s / 0s | no | - / - | record |
| dfx86zwk0ugowc | kura:pool_region | main metrics | source condition | 60s / 0s / 0s | no | - / - | record |
| ffuscyncueo74d | Kura Cache Rejecting Runner Traffic | main metrics | threshold | 60s / 20m / 0s | no | OK / Error | policy |
| bfxmy59vtljpca | Linux fleet cannot seat a shape | main metrics | threshold | 60s / 10m / 0s | no | OK / Error | policy |
| bfwuqacoo9ypsd | Runner Box Missing Kata Runtime | main metrics | threshold | 60s / 20m / 0s | no | OK / Error | policy |
| efss9ss24579ce | Runner Host Disk Buffer | main metrics | threshold | 60s / 15m / 0s | no | NoData / Error | policy |
| afuvzdl0z4mwwe | Runner Host PN VLAN Missing | main metrics | threshold | 60s / 10m / 0s | no | OK / Error | policy |
| bfss9votttr7kb | Runner Machine Stuck Failed | main metrics | threshold | 60s / 30m / 0s | no | OK / Error | policy |
| ffvr99w48mltsb | Runner job replica divergence | main metrics | threshold | 60s / 15m / 5m | yes | OK / Error | policy |
| afx2w6cpurk00b | Runner pool starved | main metrics | threshold | 60s / 10m / 0s | no | OK / Error | policy |
| afsd33dx5fhmoc | Runner queue age | main metrics | threshold | 60s / 5m / 5m | no | OK / Error | policy |
| ffxqtj0ye58g0b | Build ingestion queue not draining | main metrics | threshold | 300s / 10m / 0s | no | OK / Error | Incidents |
| bfjdlkov58oowc | Build processing duration | main metrics | threshold | 300s / 5m / 2h | no | OK / Error | policy |
| bfjdm39mehm2oa | Build queue duration | main metrics | threshold | 300s / 5m / 2h | no | OK / Error | policy |
| dfoiu6lo8k5c0a | CNPG Backup Age Too Old | main metrics | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| efoitidkfdm2oa | CNPG Connection Usage High | main metrics | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| dfoitn3wti3nkb | CNPG PVC Disk Usage High | main metrics | threshold | 300s / 5m / 0s | no | OK / Error | policy |
| bfoitfmli7im8d | CNPG Postgres Instance Down | main metrics | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| cfsogt8cgh14wc | CNPG Replication Link Break | main logs | threshold | 300s / 0s / 0s | no | OK / OK | policy |
| efoits4looikgb | CNPG Replication Slot Lag High | main metrics | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| dfsogql23ey9sc | CNPG Sync Replication Degraded | main metrics | threshold | 300s / 1m / 0s | no | NoData / Error | policy |
| afoitkr3lm48wf | CNPG Waiting Backends Detected | main metrics | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| efoqc5q9vs934a | Cardinality explosion - rapid active series growth | usage | threshold | 300s / 5m / 0s | no | NoData / Error | policy |
| ffgvpamv9xy4gf | HTTP request endpoint duration | main metrics | threshold | 300s / 1h / 5h | no | OK / Error | policy |
| efgx4im415clcc | HTTP request processing endpoints duration | main metrics | threshold | 300s / 5m / 1h | no | KeepLast / Error | policy |
| bfse8jhbbhvcwe | High Forbidden (403) Response Ratio - Production | main metrics | threshold | 300s / 5m / 0s | no | OK / Error | Incidents |
| cfsogu69cr1fkc | Host NIC Carrier Flap | main metrics | threshold | 300s / 0s / 0s | no | OK / OK | policy |
| dfkmrxsh5yz9ce | Pod CrashLoop / Frequent Restarts | main metrics | threshold | 300s / 5m / 20m | no | NoData / Error | policy |
| dfkmt5dtpx43kb | ProcessBuildWorker - jobs being discarded | main metrics | threshold | 300s / 10m / 0s | no | Alerting / Error | Incidents |
| cfl2e4b9eg8aoc | ProcessXcresultWorker - jobs being discarded | main metrics | threshold | 300s / 10m / 0s | no | Alerting / Error | Incidents |
| bfwtzbpbgelfke | Remote processing consumer is losing its slots | main metrics | threshold | 300s / 15m / 0s | no | OK / Error | policy |
| cfwbxvlcr6p6oa | Remote processing queue consumer takes work but completes none | main metrics | threshold | 300s / 20m / 5m | no | OK / Error | policy |
| ffeb6l2ax5qtcf | Slow ClickHouse query | SQL | threshold | 300s / 2m / 10m | no | OK / Error | policy |
| efjdlt32nztoga | XCResult processing duration | main metrics | threshold | 300s / 5m / 2h | no | OK / Error | policy |
| bfoinizezjim8c | XCResult queue depth | main metrics | threshold | 300s / 5m / 5m | no | OK / Error | policy |
| ffjdm0l99i9z4a | XCResult queue duration | main metrics | threshold | 300s / 5m / 2h | no | OK / Error | policy |
| dfx5a04wnfri8d | Web - LCP p50 above the Core Web Vitals good threshold | main logs | math | 60s / 30m / 0s | no | OK / Error | policy |
| ffx5dpqxovg8wf | Web - LCP p75 failing Core Web Vitals | main logs | math | 60s / 30m / 0s | no | OK / Error | policy |
| cfx5a1c7ikjy8c | Web - LCP p90 in the Core Web Vitals poor band | main logs | math | 60s / 30m / 0s | no | OK / Error | policy |
| cfx5a2f55po8wf | Web - LCP p95 sustained slow tail | main logs | math | 60s / 30m / 0s | no | OK / Error | policy |
| efx5a3mn2fwg0c | Web - LCP p99 pathological tail | main logs | math | 60s / 30m / 0s | no | OK / Error | policy |
| cfx5a5idkbgg0c | Web - browser vitals telemetry missing | main logs | threshold | 60s / 2h / 0s | no | Alerting / Alerting | policy |
| afntaseohpji8d | Anomaly: Logs Usage (Medium sensitivity) | usage | source condition | 60s / 1m / 0s | no | KeepLast / Error | Slack #notifications 2 |
| ffntarv51sxz4b | Anomaly: Metrics Usage (Medium sensitivity) | usage | source condition | 60s / 1m / 0s | no | KeepLast / Error | Slack #notifications 2 |
| cfntasv4t4r9ce | Anomaly: Traces Usage (Low sensitivity) | usage | source condition | 60s / 1m / 0s | no | KeepLast / Error | Slack #notifications 2 |
| dfntaqd25fzswd | Global Spend: 100% of $2,000 | usage | source condition | 60s / 1m / 0s | no | KeepLast / Error | Slack #notifications 2 |
| dfcubw1m2eygwb | Global Spend: 85% of $1,500 | usage | source condition | 60s / 1m / 0s | no | KeepLast / Error | Slack #notifications 2 |
| sm-failed-executions-5m-15b8b2b7 | ProbeFailedExecutionsTooHigh [5m] | synthetic main logs, synthetic main metrics | math | 60s / 0s / 0s | no | OK / KeepLast | policy |
| sm-http-latency-avg-5m-15b8b2b7 | HTTPRequestDurationTooHighAvg [5m] | synthetic main metrics | source condition | 60s / 0s / 0s | no | OK / KeepLast | policy |
