# Managed cache DNS

`zone.yaml` is an operator-applied CloudFormation stack for the delegated
`cache.tuist.dev` zone and three distinct runtime IAM policies. The zone is
retained on stack deletion. No workflow applies it automatically.

Keep bootstrap, rollback, and the repeatable staging test sequence in `README.md`.
Record completed runs, failures, measurement limits, and fixture cleanup in
`staging-validation.md`; do not treat a bounded soak as multi-day validation.
The controller owns box health checks; external-dns alone writes account A/TXT
records; cert-manager writes ACME TXT challenges. Do not combine their credentials.

Managed canary enables stable advertising and hand-out on merge. Production
prepares the same infrastructure but requires the `kura_stable_hostname`
FunWithFlags account/global opt-in; absent is off. Keep that gate on both intent
and hand-out. `wait-for-certificate.sh` blocks environment promotion until the
shared certificate includes both DNS zones and is Ready at its current
generation, preventing overlapping initial ACME issuance in the cascade.

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

`../kura-controller/cmd/staging-soak` adds bounded persistent-connection and
DNS/latency evidence for the fixed staging fixture. Distinguish its fresh
TCP/TLS readiness timings from historical native-client `/up` telemetry.
