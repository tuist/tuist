# Rack node workloads

This release is deployed after the main tuist release, without waiting for rack
readiness. Offline racks must never roll back the server deployment. Inputs are
the main chart's defaults and environment values; deployment pins images on both
releases.

`kura-volumes-csi.yaml` runs only on `kuraVolumesCSI.rackPools`; the main CSI
DaemonSet excludes those pools. Shared driver identity, RBAC and StorageClasses
remain in the main release. Keep host mounts, projected key identity and sidecars
identical; `infra/kura-volumes-csi/internal/driver/rack_chart_test.go` verifies
parity and distinct ownership. Preserve the driver while any claim exists.
