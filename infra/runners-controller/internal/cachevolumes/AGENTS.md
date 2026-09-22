# Linux snapshot cache volumes

Ceph RBD private clones used by `cmd/cache-volumes`. See
[design and runbook](../../cache-volumes.md).

- Never expose Ceph credentials, host devices, another clone or the journal to
  workflows. Guests see only `pods/<pod UID>` through kubelet SubPathExpr.
- Server identity comes from the proven executed job and GitHub App metadata;
  bind agent requests to source pod IP, node and UID. Never trust forwarded IPs.
- Persist the resource identity before creation. Each job has its own image.
  Retry operations without formatting exposed filesystems or publishing twice.
- Host/per-pod admission rejection must journal the server-issued allocation as
  deleted before returning. Reconcile its acknowledgement across report failures
  and restarts so the server can release parent references; never attach retries
  of that rejected lease. Device discovery is host-local and must omit RBD pool
  and namespace arguments, then filter mappings by pool, namespace and image.
- Seal/delete require API pod absence AND kubelet-directory absence. Completion,
  terminal phases, timeouts, and API failures are not writer fences.
- Snapshot protection and server references preserve parents of active clones.
- Serialize per lease. Slow flattening must not block unrelated attachment.
- Use no-follow mount operations and os.Root for job-controlled tree cleanup.
- Keep disabled until real Ceph/Kata/virtiofs/container smoke validation.
- Run `go test -race ./internal/cachevolumes ./cmd/cache-volumes`.

- New cold images default to 20 decimal GB, rounded up to MiB for RBD. Clones
  inherit their parent size; changing the fleet default must not resize existing
  images. Customer-configurable capacity is a follow-up.
