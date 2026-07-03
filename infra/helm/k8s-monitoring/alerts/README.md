# Management-cluster CAPI health alerts (Pillar 2)

`capi-health.yaml` is the version-controlled source of truth for the Grafana
Cloud alert rules that page on degraded CAPI control planes, unhealthy etcd,
stuck machines, a dead management cluster, and a stalled Flux
([hive/specs/72](https://hive.tuist.dev/specs/72) Pillar 2). The rules
evaluate the `capi_*` metrics that `values-mgmt.yaml` ships from the
management cluster's kube-state-metrics CustomResourceState.

## Why these live here, not clicked together in the UI

The spec requires the alert rules to be reviewed and version-controlled like
everything else. Grafana Git Sync, which already provisions this repo's
dashboards (`infra/grafana-dashboards/`), does **not yet sync alert rules —
only dashboards and folders** ([grafana/grafana#120686](https://github.com/grafana/grafana/issues/120686)).
So for now the rules are authored here and applied to Grafana Cloud manually;
when Git Sync gains alerting support, move `capi-health.yaml` under the synced
path and drop the manual step.

## Applying to Grafana Cloud

The rules are in Prometheus/Mimir rule-group format, so either path works:

- **Grafana Cloud Mimir ruler (recommended, closest to as-code).** Load the
  file into the Grafana Cloud Prometheus (Mimir) ruler with `mimirtool`, which
  evaluates them in Grafana Cloud:

  ```bash
  mimirtool rules load infra/helm/k8s-monitoring/alerts/capi-health.yaml \
    --address="https://prometheus-prod-24-prod-eu-west-2.grafana.net" \
    --id="<tenant>" --key="<grafana-cloud-api-token>"
  ```

  Route the resulting alerts to the existing on-call path via the Grafana
  Cloud Alertmanager notification policy (match `severity=critical`).

- **Grafana-managed alert rules (UI).** Recreate each rule in the Grafana
  Cloud alerting UI using the PromQL `expr`, `for`, and `severity` from the
  file, and attach the contact point that reaches OnCall.

## Validating end to end

1. Force `EtcdClusterHealthy=False` on a non-prod control plane (or scale a CP
   machine into a stuck state) and confirm `CAPIEtcdClusterUnhealthy` pages.
2. Stop the mgmt-cluster scrape (scale `kube-state-metrics` to 0 in
   `observability`) and confirm `MgmtClusterMonitoringDown` fires from Grafana
   Cloud — proving the monitor does not fail silent with the cluster.

## Note on the Flux alert

`FluxReconciliationStalled` reads `gotk_reconcile_condition`, which requires
the Flux controller metrics (`:8080/metrics` on the `flux-system` controllers)
to be scraped. Ensure the flux-system controllers are picked up by
`annotationAutodiscovery` (or add a scrape target) before relying on it.
