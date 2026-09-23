# Managed cache DNS

`zone.yaml` is an operator-applied CloudFormation stack for the delegated
`cache.tuist.dev` zone and three distinct runtime IAM policies. The zone is
retained on stack deletion. No workflow applies it automatically.

Keep bootstrap, rollback, and the repeatable staging test sequence in `README.md`.
The client selection contract in that runbook also covers the follow-up client
cleanup's global-production-rollout merge/release hold. Multiple endpoint
responses remain unranked; global activation is not a singleton guarantee.
Preserve completed evidence with the PR rather than adding point-in-time logs
to the tree; the README links the immutable staging validation record.
One-off probe sources are preserved at an immutable revision linked from the
README; they are not maintained runtime or CI tools.
The controller owns box health checks; external-dns alone writes account A/TXT
records; cert-manager writes ACME TXT challenges. Do not combine their credentials.

Managed canary enables stable advertising and hand-out on merge. Production
and staging prepare the same infrastructure but require the `kura_stable_hostname`
FunWithFlags account/global opt-in; absent is off. This is the only server rollout
control: no environment toggle or account allowlist. Keep that gate on both intent
and hand-out. Operators use `wait-for-certificate.sh` during initial bootstrap
and hostname changes to verify both wildcard names and Ready at the current
generation. Complete initial issuance serially before the merge rollout;
routine deployments do not wait for certificates. The controller's TLS probe
remains the runtime advertising safeguard.

`staging-ci-smoke.sh` is the public stable-endpoint mode of the existing Linux
runner smoke workflow. It rejects any server or project outside the spec95
staging fixture, removes the private runner endpoint override, asserts the API
hand-out, and verifies a remote Gradle upload plus twelve fresh-process hits.
Use a temporary cache-only fixture token; remove its GitHub Actions secret after
validation. The normal runner-cache smoke mode remains independent.
Use `runner_label=ubuntu-latest` for an external public-endpoint CI soak. The
staging self-hosted runner policy denies public Kura node IPs as Cilium
`remote-node` destinations when the private endpoint override is removed;
do not weaken that policy to make this public-client check pass.
