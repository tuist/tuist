# Regional routing publication gate

This deployment gate prepares regional routing before the managed server may
publish new endpoint URLs. It is called by `server-deployment.yml` and must fail
closed on API errors, missing DNS, invalid TLS or unavailable routes.

- Use only Python's standard library and kubectl; no runtime package install.
- Never print Secret data. Peer credentials use a private temporary directory.
- Preparation preserves both old and new endpoints. Publication rollback must
  retain the regional controller configuration and certificates.
- Check that all cache replicas have completed certificate rotation and that
  canonical account hostnames have no individual DNSEndpoint records. Legacy
  compatibility records and the region's shared `peer` name are intentional.
- Test with `python3 -m unittest discover -s infra/kura-controller/rollout`.
- For a local read-only check, set `KURA_ROLLOUT_CONTEXT` explicitly; CI uses
  the deployment job's environment-scoped kubeconfig.
