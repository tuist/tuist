# Certificate trust

This boundary owns the 12-key eMudhra policy, small shell checks, Go verifier
qualification, public control fixtures, access replacement guards and the
owner-driven warm rollout runbook. See `README.md` and the dated `STATUS.md`.

- Use the existing Go, shell and Elixir stack. No Python tooling or tests.
- Do not recreate the removed generic image-overlay/publishing framework.
  Prefer qualified upstream images or each component's normal source build and
  release pipeline. Preserve prior Go `godebug default` compatibility.
- Root-store containment is not a verifier patch. Go 1.26.10 passes all eight
  intermediate-key controls; Go 1.27.1 fails. Qualify replacement SDKs by actual
  behavior and update the explicit CI/test allowlist, not numeric ordering.
- `pem-store.sh` requires OpenSSL and awk. Never filter private-key material or
  protective TRUSTED CERTIFICATE AUX data as ordinary public roots.
- `java-store.sh` is only for password-changeit public SDK cacerts. Refuse private
  identities and unsupported entry types; let keytool rewrite its own format,
  then independently check the resulting PEM export before atomic replacement.
- `guard.sh` reads deployment images only, using kubectl and jq. Keep management
  access and HCCM guards fail-closed, including permission/parse errors. Human
  acknowledgement records qualification, not JIT authorization.
- Never execute audited input images, extract an untrusted rootfs to disk,
  disable verification, read Kubernetes Secrets or fetch admin kubeconfigs.
- Do not merge the entire mitigation as one rollout. Main path filters fan out
  into several owners, including production-only and parallel gateway deploys.
  Split by owner and qualify each step before the next. Do not create branches,
  worktrees or live mutations without human authorization.
- Preserve active jobs, min-warm floors, caches/PVCs, Kura health gates/pauses and
  a patched rollback floor. Ready/inventory is not verifier qualification.
  Cache-volume agents and singleton/access components are not uniformly warm.
- Packer trust changes must run only inside fresh guest VMs. Apple native denial
  does not protect OTP's root cache; qualify native and effective OTP behavior
  independently. Never run guest trust mutations on the developer host.
- Keep named Docker contexts, fallback stages, callers and actual checker/policy
  release inputs aligned. Runbook-only edits must not rebuild fleets.
- Validate with `GOWORK=off GOTOOLCHAIN=go1.26.10 go test -count=1 ./...` here,
  `go run .` under the same qualified SDK, isolated ExUnit, shell syntax/lint,
  workflow lint and Packer format/syntax. These do not qualify deployed verifiers.
