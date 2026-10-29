# Personal execution environments

`Atlas.Environments` registers opt-in owner-private native installations and
deployment-configured hosted providers. The hosted contract, Tuist OIDC setup,
generation fencing and retention are in [environment providers](../../../docs/environment-providers.md).
Hosted commands use the same ledger and privacy boundaries; terminal execution is
limited to 600 seconds, with no native credentials installed. Models,
provider credentials, sessions, checkpoints and all orchestration remain on the
server. The device receives only the three explicit tool calls. File tools are
contained in the selected project. Terminal starts there but runs as the macOS
user without a folder sandbox and can access outside it. The owner explicitly
opts into terminal access per Mac; commands run without per-command approval
(at most 8,000 UTF-8 bytes).
Never expose these through MCP discovery, workflows, shared threads or research
children. This is a deliberate exception to MCP parity and Orbit's otherwise
read-only server tools. `display` is configuration only, not screen authority.

Registration accepts names and opaque project UUIDs, never local absolute paths.
Owner and native OAuth client are immutable. Disabled is the default. Updating
permissions/projects or disabling advances a version and clears the short online
lease. Renewals must retain their joined version; only fresh joins/HTTP polls can
acquire the new one. Closing clears only that connection's lease. HTTP polling is
an authoritative transport fallback, never an independently supervised server loop.

`Commands` is the durable dispatch ledger, unique on the existing Orbit tool card.
Lock thread, run, environment, then command. File tools retain their bounded
synchronous 60-second wait and known-result recovery. Terminal reservation returns
a durable queued ticket immediately, without changing Orbit's run/turn
ceilings. The per-Mac terminal opt-in authorizes dispatch;
claim accepts only the digest. Digest binds the command
ID, environment ID/version, frozen project, arguments and execution timeout.
Dispatch expires ten minutes after first reservation. Claim starts a fixed
1,800-second execution deadline plus a separate five-minute result-delivery grace.
Progress is encrypted, monotonic and bounded to 48 KiB, never a lease extension.
Claimed commands never become dispatchable again. One active or unknown terminal
job per thread is enforced under the thread lock, across runs and selections.
Only a successful originating run may detach its job; checkpointed attempts keep
the same command. Cancellation/archive, history revocation and configuration
changes fence new results. Missing claimed results become explicitly unknown,
never presumed stopped or automatically rerun. Owner cancellation of a claimed
job only sets `cancel_requested`; the device must acknowledge its actual outcome.
Identical accepted result retries remain idempotent after the originating run ends.

Confirmed terminal completion atomically updates encrypted card evidence, appends
a generic system notice with bounded encrypted `device_output`, and stores that
notice ID on the command. The existing `Runs.follow_up` and Oban run/job recovery
own continuation, including waiting behind an active run. The bounded notifier
outbox sweep also recovers a replica lost between that run's final commit and
follow-up creation; archive retires pending completion notices permanently.
No new model runtime or plaintext output in system messages/jobs/audits exists. Automatic continuations
recheck their original source at follow-up, start, model dispatch and final reply;
cancellation and unknown never trigger inference. Fresh human runs still
freeze the thread's current selection, including server-only or another Mac.
Activity is a terminal-only owner projection: all active jobs first, at most 32
rows, 48 KiB UTF-8 tails and 256 KiB aggregate output, additionally bounded below
the native 1 MiB JSON reader even with control-character escaping. Exact commands
are preserved; older settled rows/tails may be omitted to fit. A rotating bounded
notifier sweep expires pending/claimed jobs independently of model sessions.

Commands and results use encrypted, inspect-redacted binary fields. Native tool
card renderings use encrypted `device_input`/`device_output`; ordinary Atlas cards
keep their existing storage. Session telemetry's Orbit allowlist and Phoenix
parameter filters exclude command/argument/output payloads. Audits include IDs,
fixed action/tool names, permission booleans and project counts, never paths,
commands, outputs or arbitrary native error details. No seeds register fake online
devices or opt anyone in. Retention/legal export is in `data-export.md`.

The native wire contract and fixed error codes are in
`lib/atlas_web/controllers/AGENTS.md#personal-execution-environments`.
