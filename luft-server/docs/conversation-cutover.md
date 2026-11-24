# Tuist conversation cutover to Luft

This procedure transfers a whole instance's threads, direct messages and halls
(Luft calls them lounges). Run it offline during an approved maintenance window.
The tools do not delete source data or change upstream accounts or membership.
Do not run them against a serving destination.

## Preconditions and backups

1. Rehearse against restored PostgreSQL and object-storage backups first. Keep
   all Tuist Vault key versions that encrypted historical records. Provision a
   stable, separate Luft `SECRET_KEY_BASE` and back it up with restricted access.
   Both `CONDUKT_BASHKIT_DISABLE=1` and `CONDUKT_MICROSANDBOX_DISABLE=1` must be
   present when building Luft, including its Condukt dependency.
2. Apply Luft migrations through the thread, agent storage and runner credential
   migrations. Keep its conversation tables, `agent_sessions`, `agent_objects`
   and `thread_runner_credentials` empty. Existing login sessions can remain;
   the importer will not associate them with historical work.
3. Verify the exact upstream account ID to current handle mapping using Tuist's
   authenticated API or an approved database snapshot. Supply that map as
   `accounts:`. The importer requires equality with the exported mapping and
   checks that the conversation rows reference exactly those account IDs.
   It does not fetch upstream identities or authorize a rename/remap. Stop if
   an account has changed identity or handle since the source snapshot.
4. Put **all** Tuist conversation ingress into maintenance: HTTP, WebSocket,
   MCP, callbacks, cron and jobs, including snooze/recovery workers. Disconnect
   native runner clients and stop their polls. Drain agent hosts, then stop
   the runner supervisor on every replica. Drain may release leases as wanted;
   do not leave any scheduler running that could claim them again. Confirm no
   thread agent has `host` or `lease_expires_at` set. The exporter rejects such
   leases, including expired leases that still have an owner.
5. Stop background journal writes and object-store retention/cleanup. Obtain
   database and object-store backups at this quiescent point. The exporter holds
   PostgreSQL SHARE locks but cannot fence remote object-store writers. The
   `quiesced: true` acknowledgement records the operator's assurance, not an
   automatic distributed maintenance switch.
6. Keep all Luft endpoints, runner hosts, recovery/snooze/notification jobs and
   cron stopped too. Use a dedicated offline VM with only required Repo,
   encryption and storage processes, not the normal application supervision
   tree. Review startup paths before running a release evaluation command:
   booting the normal application can resume work before import or verification.
   Do not call `Application.ensure_all_started(:tuist)` or
   `Application.ensure_all_started(:luft_server)` in this maintenance VM.

The tools process the snapshot in memory and hold table locks for the operation.
Size the VM, database transaction timeout, disk and maintenance window using the
rehearsal. Do not enable SQL parameter logging, shell tracing, IEx history, crash
dumps or request/error reporters that might capture plaintext or credentials.

## Export API and file handling

Load `Tuist.LuftConversationExport` in the offline source environment. Start only
its configured Repo, Vault (with the historical keys), storage dependencies and
the dependencies those processes need. The exporter's retained, read-only
`Tuist.LuftConversationExport.LegacyS3Bucket` lists and reads the bucket from
`Tuist.Environment.s3_bucket_name/0` through ExAws. It does not depend on the
runtime agent SessionStore or Bucket modules. No conversation schema, context,
host or runner process needs to start.

```elixir
{:ok, %{binary: archive, sha256: sha256}} =
  Tuist.LuftConversationExport.export(quiesced: true)

# On a private encrypted volume, with the parent directory restricted to 0700:
{:ok, file} = File.open("/secure-cutover/conversations.etf", [:write, :binary, :exclusive])
:ok = File.chmod("/secure-cutover/conversations.etf", 0o600)
:ok = IO.binwrite(file, archive)
:ok = File.close(file)
```

Set `umask 077` before starting the maintenance VM so the file has no public
creation window. Export returns `{:error, reason}` on a lease, decrypt, database
or storage failure. It returns no partial archive. Options `repo:`, `bucket:`
and `decrypt:` support restored/offline adapters and tests; production operators
should use the defaults unless they have reviewed the adapter.

Configure a persistent offline bucket override under the exporter itself:

```elixir
config :tuist, Tuist.LuftConversationExport,
  bucket: {ApprovedReadOnlyLegacyBucket, adapter_options}
```

Review and migrate any previous runtime SessionStore bucket override to this key
before removing the runtime. The exporter no longer reads that runtime setting.
No shared configuration change accompanies this tool. Keep the default adapter's
ExAws endpoint/credential configuration and `s3_bucket_name/0` available during
the retention window. Grant the offline identity list/get access only.

Treat the archive as plaintext customer data **and plaintext secrets**. It
contains checkpoints, tool results, prompts, private diffs and journal records
that may hold credentials. Do not put it in Git, CI artifacts, chat attachments,
shared temporary directories or an unencrypted bucket. Transfer it using an
authenticated encrypted channel. Send its lowercase SHA-256 digest through an
independent authenticated channel and record approval, source backup identity,
code revision and digest in the restricted change record. A digest supplied by
the same untrusted party as the file does not authenticate it.

## Format version 1

The archive uses Erlang external term format, uncompressed, with string map keys:

```text
%{
  "format" => "tuist-luft-conversations/1",
  "accounts" => [{upstream_integer_id, current_handle}, ...],
  "tables" => %{legacy_table_name => [%{column_name => Postgrex_value}, ...]},
  "objects" => %{original_object_key => decrypted_object_bytes}
}
```

The table allowlist includes `threads`, `thread_messages`, `thread_participants`,
`thread_ship_approvals`, `thread_runs`, `thread_tool_calls`, `thread_runners`,
`thread_runner_requests`, `thread_inboxes`, `halls`, `hall_members`,
`hall_messages` and the `kind = 'thread'` subset of `agent_sessions`.
UUIDs retain Postgrex's 16-byte representation. Timestamps retain their decoded
Postgrex types. The encrypted database columns `thread_runs.checkpoint` and
`thread_tool_calls.result` contain **decrypted bytes** in the archive. The
exporter removes runner token hashes. It includes all objects under
`agents/thread/`, including retained older manifests and orphaned segments.

The importer renames hall tables/foreign keys and the `hall` kind to `lounge`.
It preserves direct-conversation keys, UUIDs, request hashes, tool fingerprints,
positions, read cursors, participants, approvals, timestamps and historical run
statuses. Unknown source columns cause an SQL error rather than silent dropping.
Accounts, memberships, OAuth grants and live-activity/device credentials remain
outside this archive. Attachments retain their metadata and storage references;
this operation does not move attachment/media objects. Preserve their storage and
access paths separately before removing any upstream media route.

## Import API

In the offline Luft VM, start its Repo and required crypto dependencies, without
the application supervisor. Use the PostgreSQL-backed
`LuftServer.Agents.Bucket` for runtime journals after cutover.

```elixir
archive = File.read!("/secure-cutover/conversations.etf")

{:ok, %{rows: counts, objects: object_count}} =
  LuftServer.ConversationImport.import(archive,
    maintenance: true,
    sha256: verified_sha256,
    accounts: verified_upstream_id_to_handle_map
  )
```

The importer requires the exact table set and the verified digest. It takes
ACCESS EXCLUSIVE locks on the destination conversation/storage tables and rejects
any existing rows, even for a disjoint account. It runs inserts, journal writes,
and journal readback in one PostgreSQL transaction. A conflict, malformed term,
invalid foreign key, missing referenced journal segment or decryption/readback
failure rolls back the transaction. It has no merge, upsert or force mode.

The importer encrypts checkpoint/result plaintext through Luft's
`Threads.EncryptedBinary.dump/1`. It encrypts each journal object through the
encrypt callback from `Agents.SessionStore.store/3`, then inserts into Luft's
PostgreSQL object bucket on the same connection. Both sides read snapshots and
journals with Condukt without an epoch, avoiding lease fencing writes. Object
contents retain their original bytes across decrypt/re-encrypt boundaries.
The importer reads the stored ciphertext back on its transaction connection and
gives Condukt an immutable readback bucket. Condukt reads segments in tasks;
allowing those tasks to query PostgreSQL would lose transaction visibility and
block behind the importer's own table locks.
As Condukt does, the tools decode trusted journal terms that can introduce tool
error atoms. Do not accept an archive from an untrusted sender or expose this API
as a network upload endpoint. Outer ETF decoding uses `:safe`; preserve compatible
OTP/Elixir/Condukt versions and preflight historical snapshot types during rehearsal.

## Reauthorization and verification gate

The importer sets `owner_session_id` and `author_session_id` to NULL. It preserves
historical run/session IDs without treating them as OAuth delegation. It clears
lease hosts/expirations, sets all imported `wanted` values to false and clears
`wanted_at`. It preserves lease epochs and sequence numbers. It replaces runner
token hashes, marks historical runners revoked and creates no credential bindings.
It cancels pending/claimed runner requests while retaining their payloads/results.

Before starting Luft's supervisors:

- Compare source/export/import row counts and IDs for each table, accounting for
  hall renaming and the thread-only agent lease filter. Compare object counts and
  decrypt/readback representative historical snapshots and journals, including
  interrupted tools and approved shipping work. Compare plaintext bytes rather
  than ciphertext, since Luft uses a different key and fresh nonces.
- Check that every imported owner/author session reference is NULL, no agent
  wants a host, no host or lease expiration remains, all runner records have a
  revocation timestamp, no runner credential binding exists, and no imported
  runner request remains pending/claimed.
- Test Luft's authorization gates against imported queued/running/waiting runs
  and pending/approved shipping approvals with **no new consent**. Keep all
  execution/recovery supervisors stopped until those gates pass. Historical
  statuses and approval facts alone must not authorize execution or publishing.
- Require users to sign in to Luft and give new, exact consent through Luft's
  authorization flow before attaching a live owner session or requesting a new
  lease want. Do not infer an owner session from matching user/account IDs or
  backfill message authors with a current session. Require runner registration
  in Luft; keep old runner IDs only as historical references.
- Confirm tenant isolation, DM participants, chronological message positions,
  unread cursors, attachment access and request-retry fingerprints in the UI/API.
  Do not test this by resuming real historical commands without user consent.

Record approval of these checks before enabling traffic and supervision. Keep
Tuist conversation writers disabled after routing clients to Luft. Keep upstream
account/membership/OIDC services available.

## Rollback and retirement

On import failure, leave both runtimes stopped and inspect the restricted failure
record. Correct the source backup/configuration and create a fresh export if
needed; do not edit encrypted objects or suppress an import conflict. If the
import committed, a rerun must fail because the destination is not empty. Use an
approved disposable restore or a fresh destination for another rehearsal.

Before Luft accepts new writes, an operator may roll back routing to the unchanged
Tuist snapshot and resume Tuist supervision after verifying that Luft stayed
quiescent. After Luft accepts writes, rollback requires reconciling that new
history; these tools do not implement reverse transfer or conflict merging.

Retain legacy tables, original encrypted journal objects, backup manifests, Vault
key versions and this offline exporter until an operator approves deletion under
the applicable retention policy. Keep Repo, Vault, the configured object-bucket
adapter (the nested read-only `LegacyS3Bucket` by default), Environment's bucket
configuration and Condukt's object-store reader available with the exporter after
removing the runtime thread/hall/agent contexts. Retain the old tables and objects;
removing runtime modules does not authorize their deletion. Nothing here schedules deletion.
After the approved validation/rollback window, remove plaintext staging copies
and their encrypted-volume keys under the organization's secure disposal policy;
do not assume overwriting a file securely erases SSD or snapshot copies.

## Regression commands and remaining rehearsal work

Run the focused database tests in `server/` and `luft-server/`:

```sh
CONDUKT_BASHKIT_DISABLE=1 CONDUKT_MICROSANDBOX_DISABLE=1 \
  mix test test/tuist/luft_conversation_export_test.exs
# From luft-server/:
CONDUKT_BASHKIT_DISABLE=1 CONDUKT_MICROSANDBOX_DISABLE=1 \
  mix test test/luft_server/conversation_import_test.exs
```

The source tests use real PostgreSQL and Tuist Vault encryption. Destination tests
use real PostgreSQL, Luft encryption, native journal readback, mapping/maintenance
checks, late-failure rollback and representative history fields. These focused
tests do not replace a production-sized, two-runtime rehearsal using restored
object storage, all historical key versions, every snapshot shape, multi-replica
maintenance enforcement and consent-gated recovery. The in-memory bucket in the
source regression and mocked ExAws checks do not test live S3 pagination or
credentials. The default-adapter regression verifies encrypted-object retrieval,
decryption, Condukt readback, listing cursor forwarding and sanitized read errors.
No test here grants permission to run a live import or delete source history.
