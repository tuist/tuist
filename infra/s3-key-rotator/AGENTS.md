# S3 key rotator

CronJob that gives the platform storage short-lived Tigris keys, since Tigris has
no STS. Each run mints a `no_default_allow`, bucket-scoped key with an
organization admin key, checks that it reaches its buckets, and writes it to one
Secret. It deletes a key named `<prefix><timestamp>` only when it is not the
current key or a retained previous key, retention has passed since the Secret's
last rotation, and it was minted more than interval + retention ago. Chart wiring: `infra/helm/tuist/templates/s3-key-rotator.yaml`
(`s3KeyRotation` values). Workloads read the Secret as files through
`TuistCommon.AWS.CredentialFiles`.

- Never delete a key something may still use. Every non-current key was
  replaced at or before the Secret's last rotation, so the rotation-time gate
  holds however long a key stayed current (stalled runs), and a run that had to
  recreate the Secret or rotated after losing its annotations deletes nothing
  for retention. The minting-time gate protects a key a concurrent run has not
  stored yet (a manual `kubectl create job` ignores `concurrencyPolicy`). Keep
  both; do not reduce cleanup to the annotations.
  `Config.Validate` enforces retention ≥ 12h15m (presigned URLs last 12 hours)
  and interval > retention; keep both.
- A Secret write that fails ambiguously (timeout, dropped connection) is read
  back before the new key is deleted, and a current key missing from the list is
  rotated only if it no longer works.
- Only names that are exactly the prefix plus a timestamp are ever deleted, so a
  longer prefix sharing this one's start is safe. Still keep prefixes unique per
  Secret.
- A minted key that fails verification or cannot be stored is deleted in the
  same run; one a crashed run leaves behind is deleted after interval + retention.
- To replace a key early, such as after a leak, run a Job with `--rotate-now`:
  `kubectl create job --from=cronjob/<release>-tuist-s3-key-rotator <name> --dry-run=client -o json | jq '.spec.template.spec.containers[0].args += ["--rotate-now"]' | kubectl create -f -`.
  Cleanup is unchanged, so the replaced key keeps working for the retention;
  revoke a leaked key in Tigris yourself if it must stop at once.
- Tigris IAM calls follow Tigris's own SDK (`tigrisdata/storage`, `packages/iam`):
  `https://iam.storageapi.dev`, SigV4 as service `s3`, region `auto`. They are
  tested against a fake server only.

Run `go test ./...` and `go vet ./...` here. The image is built by
`.github/workflows/s3-key-rotator-image.yml` (`:sha-<commit>`); it is not yet a
released component.
