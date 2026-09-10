# GitLab CI runner integration

`Tuist.Runners.GitLab` acquires jobs using GitLab's Runner protocol and queues
them in the shared runner lifecycle. A connection binds an encrypted runner
authentication token to an account and profile. GitLab assigns immediately;
there is no reservation-release API. Never request a job twice on a transport
retry. Persist the encrypted assignment and lifecycle together, and fail the
assignment upstream if persistence fails.

- Keep reusable runner credentials on the server. Dispatch only the acquired
  job response and a job-scoped Tuist report token.
- `Client` pins public DNS and disables redirects through the existing SSRF
  guard. Self-managed instances must be reachable over public HTTPS.
- Assignment responses contain objects; successful job updates may return a
  scalar JSON status. Check cancellation headers before HTTP error handling.
- Queue at most five waiting assignments per connection, refresh their status,
  and fail them after ten minutes without a machine. A stopped machine fails
  through GitLab with `runner_system_failure`; never replay its job response.
- Clear execution payloads on completion and after twelve hours. Retain only
  identity metadata for dashboard links and history. UI queries omit payloads.
- Shared account cache volumes/signing grants are withheld until GitLab job
  trust can be established independently of overridable CI variables.
- `infra/linux-runner-image/gitlab-runner/` embeds the upstream shell executor
  for both Linux and macOS. Keep the protocol version aligned with its pinned
  upstream commit. Job scripts, artifact handling, cancellation and masking
  remain upstream responsibilities.
- Tests use synthetic tokens and mocked requests or a local fake coordinator.
  Never use staging or real GitLab credentials for local validation.
