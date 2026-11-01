# Rack node workloads

This release is deployed after the main tuist release, without waiting for rack
readiness. Offline racks must never roll back the server deployment. Inputs are
the main chart's defaults and environment values; deployment pins images on both
releases.

`kura-volumes-csi.yaml` runs every Kura CSI node plugin: `kura-volumes-csi-rack`
on `kuraVolumesCSI.rackPools` and `kura-volumes-csi-node` on the remaining cache
pools, so a broken rented Kura node cannot roll a deploy back either. Driver
identity, RBAC, admission and StorageClasses remain in the main release.
`kura-volumes-csi-node` keeps the name and immutable selector the main release
created; the deploy moves the live object with
`.github/scripts/helm-move-release-objects.sh` before adopting it, and its pod
template must not change in that move. Rolling the tuist release back to a
revision that still rendered the plugin fails on that ownership: move the object
back with the same script first. `rackNodes.kuraCachePools` copies the
main chart's pool helper. Keep host mounts, key identity and sidecars identical;
`infra/kura-volumes-csi/internal/driver/rack_chart_test.go` verifies parity,
pool helpers and ownership. Preserve the driver while any claim exists.

The same per-node thin configuration and allocator socket contract applies to racks. Shared thin StorageClass/topology and pod UID settings remain owned by the main release.
