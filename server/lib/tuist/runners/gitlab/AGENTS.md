# GitLab CI runner integration

`Tuist.Runners.GitLab` acquires jobs using GitLab's Runner protocol and queues
them in the shared runner lifecycle. A connection binds an encrypted runner
authentication token to an account and instance URL. Each GitLab 19.3+ job
selects its account-owned profile from `CI_JOB_TAGS`; require exactly one Tuist
profile tag, ignoring unrelated tags. Never fall back to `CI_RUNNER_TAGS` or a
default machine. GitLab assigns immediately;
there is no reservation-release API. Never request a job twice on a transport
retry. Persist the encrypted assignment and lifecycle together for routable jobs, and fail the
assignment upstream if persistence fails.

- Keep reusable runner credentials on the server. Dispatch only the acquired
  job response and a job-scoped Tuist report token.
- `Client` pins public DNS and disables redirects through the existing SSRF
  guard. Self-managed instances must be reachable over public HTTPS.
- Assignment responses contain objects; successful job updates may return a
  scalar JSON status. Check cancellation headers before HTTP error handling.
- Queue at most five waiting assignments per connection and refresh their
  status. GitLab starts a job's timeout at acquisition, so never fail an
  assignment for waiting before that timeout (capped by payload retention).
  Acquire only while each platform's remaining concurrency fits the sum of
  its queued assignments plus one more as large as the largest. Settlement,
  not the retention purge, clears waiting payloads, and the GitHub-only
  `StaleQueuedJobsWorker` must never select GitLab rows. A stopped machine
  fails through GitLab with `runner_system_failure`; never replay its job
  response.
- Poll-worker uniqueness expires after two minutes so a server restart does
  not block a connection until the global Oban rescue interval elapses.
- Clear execution payloads on completion and after twelve hours. Retain only
  identity metadata for dashboard links and history. UI queries omit payloads.
- Parse GitLab's per-line UTC timestamp, hexadecimal stream ID and continuation
  flag before section markers. Keep ANSI colors for the shared log renderer,
  but remove erase-line controls used around section boundaries.
- Shared account cache volumes/signing grants are withheld until GitLab job
  trust can be established independently of overridable CI variables.
- GitLab's `cache:` keyword is backed by `Cache` through
  `RunnerJobCacheController` (`/runners/jobs/cache/*`): a presigned download
  URL, and a multipart upload whose parts are presigned one at a time, so
  archives are not capped by a single PUT. Take the account, project ID and
  ref protection from the report token's claims, which `mint_acquisition`
  copies from the coordinator's `job_info`/`git_info`; never from the request
  or CI variables. Keep protected and unprotected refs in separate key
  namespaces for reads and writes. A token without those claims gets 404 and
  the job runs without a remote cache; storage failures are 503 so the
  executor retries.
- Every started upload schedules `AbortGitLabCacheUploadWorker` a day out.
  Incomplete uploads never appear in object listings, so retention cannot
  reclaim them. Aborting a completed upload is a no-op, so completion does not
  cancel the job.
- Cache archives live under `runner-gitlab-cache/<account handle>/` through
  `Storage`, so custom-storage accounts write to their own bucket. Hosted
  retention lists only that prefix, expires orphaned handles with the Air
  window, and account deletion purges the prefix.
- `infra/linux-runner-image/gitlab-runner/` embeds the upstream shell executor
  for both Linux and macOS. Keep the protocol version aligned with its pinned
  upstream commit. Job scripts, artifact handling, cancellation and masking
  remain upstream responsibilities.
- Tests use synthetic tokens and mocked requests or a local fake coordinator.
  Never use staging or real GitLab credentials for local validation.

- Rejected assignments retain their encrypted payload and a non-secret
  `routing_error` until their trace and failure are acknowledged by GitLab.
  They never enter the dispatch queue. Polling and disconnect retry settlement;
  a trace range conflict on retry means the error was already uploaded.
- The poller advertises the Linux coordinator's platform; it does not choose a
  machine until it reads the acquired job's tags.

- Poll passes use the dedicated `runner_gitlab` queue and snooze between requests within each cron window. Inactive accounts stop early; rejected jobs do not stop subsequent acquisition. Settlement returns remaining assignments for capacity checks without a second joined query.
- Disconnect performs only account-scoped database mutations in the request process; background polling settles assignments. Idle deletion is idempotent. Routing alerts survive empty polls until a routable job is acquired.
- Persistence exceptions log their class and stack locations with argument values omitted; never log the assignment or exception message, which may contain tokens.

- Build/test insight linkage follows CLI metadata: `ci_project_handle` is the bare project path, `ci_run_id` is the pipeline ID, and `ci_host` is matched separately. Accept legacy empty hosts, but exclude a known different instance. Partial indexes on non-null payloads keep waiting-assignment and expiry queries bounded by live assignments.
