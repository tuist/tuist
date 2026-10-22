# Managed cache DNS

`zone.yaml` is the CloudFormation stack for the delegated `cache.tuist.dev`
zone and three distinct runtime IAM policies. The zone is retained on stack
deletion. `.github/workflows/cache-dns.yml` plans it on pull requests and applies
it on `main` through `.github/scripts/cache-dns-change-set.sh`; both refuse a
change set that replaces or removes the hosted zone.

`deploy-role.yaml` is the one operator-applied stack: GitHub's OIDC provider, a
pull-request role that can only create change sets, a `main` role that can also
execute them, and the CloudFormation execution role that holds the Route53, Logs
and IAM permissions. Neither workflow role may change it. Keep record-set writes
out of the execution role; external-dns, cert-manager and the controller own them.

Keep bootstrap, rollback, and the repeatable staging test sequence in `README.md`.
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

The optional shared activation gateway uses a Route53 wildcard fallback while exact regional latency records keep precedence. Production enables the gateway on the general worker pool and ingress DNS sourcing through nginx-grpc after pinned production validation. Other environments keep both off; rollout and rollback are in `../kura-controller/activation.md`. Do not create wildcard owners in multiple environments.
