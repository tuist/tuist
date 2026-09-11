# Regional routing publication gate

This deployment gate prepares regional routing before the managed server may
publish new endpoint URLs. It is called by `server-deployment.yml` and must fail
closed on API errors, missing DNS, invalid TLS or unavailable routes.

- Use only Python's standard library and kubectl; no runtime package install.
- Never print Secret data. Peer credentials use a private temporary directory.
- Public IPv4 probes run from CI. IPv4 peer probes use `peer_probe_job.py` in the target
  cluster because runner egress excludes port 7443. Keep its image pinned,
  service-account token disabled, credentials on exec stdin/memory only, and
  both explicit cleanup and Job deadline/TTL. Never forward CA private keys.
  IPv6 public and peer probes use bounded host-network Jobs on the node owning
  the target address; do not assume the runner or Pod network supports IPv6.
  These prove node-local public-address routing, not external IPv6 reachability.
- Save the pending region subset before preparation, and gate only that subset.
  Ordinary deployments with an unchanged publication map must bypass the gate.
  Check legacy account-wide peer LoadBalancers are gone before preparation and
  publication. Keep the gate/Job/deployment time budgets consistent.
- Preparation preserves both old and new endpoints. When adding regions, retain
  the already-published subset instead of disabling publication globally and
  recreating legacy records. Publication rollback must
  retain the regional controller configuration and certificates.
- Check that all cache replicas have completed certificate rotation and that
  canonical account hostnames have no individual DNSEndpoint records. Legacy
  compatibility records and the region's shared `peer` name are intentional.
- Test with `python3 -m unittest discover -s infra/kura-controller/rollout`.
- Set `KURA_ROLLOUT_CONTEXT` explicitly for local use; CI uses the deployment
  job's environment-scoped kubeconfig. `plan` and `needed` are read-only;
  `wait` creates and cleans up the bounded peer validation Job.
