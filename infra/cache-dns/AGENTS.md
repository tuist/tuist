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
