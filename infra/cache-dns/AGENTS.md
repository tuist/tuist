# Managed cache DNS

`zone.yaml` is an operator-applied CloudFormation stack for the delegated
`cache.tuist.dev` zone and three distinct runtime IAM policies. The zone is
retained on stack deletion. No workflow applies it automatically.

Keep bootstrap, rollback, and the deferred staging test sequence in `README.md`.
The controller owns box health checks; external-dns alone writes account A/TXT
records; cert-manager writes ACME TXT challenges. Do not combine their credentials.

`../kura-controller/cmd/staging-probe` validates readiness and authenticated HTTP/REAPI blob round trips
against staging hosts only. It keeps TLS verification enabled when pinning a box
IP, accepts tokens through a local file, and writes credential-free JSONL evidence.
Its embedded `reapi-smoke.proto` is the minimal wire-compatible CAS schema used by grpcurl.

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
