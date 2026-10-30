# Environment providers

Atlas can run a private conversation's file and terminal tools in a hosted Linux
workspace. Pip, model credentials, checkpoints and orchestration remain on Atlas.
The provider gets only the authorized tool and its arguments. This is not an
agent installation or a second inference runtime.

In iOS/macOS open a private conversation's **Tool environment** picker and choose
**Tuist**. On Android use the conversation menu's **Tool environment** action.
Starting is asynchronous; wait for **Ready** before asking Pip to work there.
For example: “Clone https://github.com/example/project into /workspace/project,
inspect its tests, and make the requested change.” Public repositories work
without credentials. No repository token, SSH identity, model key or Atlas access
token is installed in the VM. Private-repository authentication is not implemented.

Selecting **Atlas server** (Android: **Server only**), choosing a different
environment, or archiving the conversation requests a pause. Closing the client
does not stop server work. Pausing retains files; it does not promise that a
running command has already stopped. Unknown command outcomes are never retried.
Restoring an archived conversation starts no work; select Tuist again to resume.
Tuist may pause idle VMs and deletes paused/errored workspaces after 14 days.
Selecting the provider after expiry starts a new empty workspace.

## Provider contract

Implement `Atlas.Environments.Provider` and register a stable, lowercase provider
ID (1–100 characters, letters, numbers or `-`) in deployment configuration:

```elixir
config :atlas, :environment_providers, %{
  "example" => %{module: MyApp.EnvironmentProvider, name: "Example"}
}
```

Provider configuration is trusted server configuration, not client/model input.
Each callback receives that configuration and the immutable
`%{owner_id: uuid, environment_id: uuid, generation: positive_integer}` identity.
There is one hosted environment per private thread/provider, with one opaque
Workspace project. It counts towards the owner's 32-registration limit.
The catalog is additive in `GET /api/me/environments`; clients select through
`PATCH /api/native/orbit/threads/:id/environment` with `{"provider":"example"}`.
Atlas authorizes owner, private history, active status and absence of an active run.
Only configured providers appear. Older servers/clients retain native selection.

| Callback | Result and requirements |
| --- | --- |
| `start(config, identity)` | `{:ok, map}` only when ready; repeated start preserves the workspace |
| `stop(config, identity)` | `{:ok, map}` after a pause; idempotent, retains files |
| `delete(config, identity)` | `{:ok, map}` after deletion; idempotent, removes files |
| `execute(config, identity, command)` | `{:ok, %{success: boolean, output: utf8}}`, or `{:error, fixed_atom}` for an unavailable/unknown outcome |

Lifecycle callbacks can be repeated and arrive out of order across replicas.
Persist the highest generation **before** the VM effect. Reject lower generations
and a start at the same generation as a stop/delete. Keep a tombstone after VM
deletion so a delayed request cannot recreate it. A later explicit selection
advances the generation. Atlas conditionally saves observed state against that
generation and uses durable Oban jobs, not a process-local session.

Execute receives only `id`, `tool`, `arguments`, `execution_timeout_seconds`.
Tools are `environment_terminal` (command up to 8,000 UTF-8 bytes, 600 seconds),
`environment_read_file` and `environment_list_directory` (workspace-relative path,
60 seconds). Arguments include a frozen opaque `project_id`. File reads must
reject traversal/symlink escape; Tuist bounds reads to 60,000 bytes and directory
enumeration to 200 names. Output is at most 65,536 UTF-8 bytes. Terminal starts in
`/workspace`, with guest-wide execution authority, not a directory sandbox.

Atlas claims the encrypted command ledger before any external effect. Never retry
execute after a timeout or uncertain transport result. A worker crash after claim
leaves the outcome unknown, even if execution never reached the provider. Confirmed
completion records encrypted evidence and continues the conversation through Orbit.
The provider must not echo bearer tokens or raw transport errors. Root private
conversations only: no MCP, workflows, shared threads or research-child execution.
Once a conversation dispatches an environment command it cannot be shared.

## Tuist adapter and OIDC setup

Apply the Atlas and Tuist migrations and upgrade all replicas before enabling
configuration. On Atlas set `ATLAS_ENVIRONMENT_OIDC_PRIVATE_KEY` to a dedicated RSA
private PEM of at least 2048 bits, identical on every replica, and set
`ATLAS_TUIST_ENVIRONMENT_ACCOUNT` to the Tuist account handle. The optional
`ATLAS_TUIST_ENVIRONMENT_URL` defaults to `https://tuist.dev` and must be an HTTPS
origin. Atlas's configured endpoint URL must be its canonical public HTTPS origin;
it is the issuer, never an incoming Host header. The key is independent of OAuth,
session and vault keys. There is no signing key in the repository or native apps.

On Tuist configure `TUIST_ATLAS_ENVIRONMENT_TRUST` as JSON, for example:

```json
{"acme":{"issuer":"https://atlas.example.org","subjects":["user:00000000-0000-4000-8000-000000000001"]}}
```

Omitting `subjects` trusts all signed Atlas users on that issuer for this account;
use an explicit allowlist for a pilot. Enable Tuist's existing account sandbox
feature flag separately. Existing sandbox quotas, shapes, capacity and idle pause
rules apply. At most 4,096 identity mappings per account are admitted, including
tombstones. Removing trust prevents new requests, including pause/delete from
Atlas; pause/delete the VMs before removing trust, or use Tuist account administration.

Atlas publishes `/.well-known/openid-configuration` and `/.well-known/jwks.json`.
It signs five-minute RS256 bearer JWTs with `iss`, `sub=user:<owner UUID>`,
`aud=tuist-environments`, `iat`, `nbf`, `exp`, `jti`,
`purpose=atlas-environment`, `account_handle`, and `environment_id`.
Tuist verifies the signature against the **configured issuer's** fixed JWKS URL,
with public-IP pinning, TLS checks, bounded asymmetric keys and a 15-minute
success-only key cache. It checks issuer, audience, purpose, account, environment,
owner and lifetime before lookup. No CI grant or Tuist access token is minted.
Rotation/revocation must account for that cache and already issued five-minute
tokens. Current trust configuration is checked on every request.

The adapter uses bearer-only JSON endpoints under
`/api/environment-providers/atlas/:account_handle/:environment_id`:
`PUT /` starts, `POST /pause` stops, `DELETE /` deletes, `POST /exec` executes.
Every body includes integer `generation`; exec additionally includes the command
fields above. Lifecycle success returns `{state}`; execution returns
`{success, output}`. Invalid identity is 401, stale generation 409, invalid input
422, disabled provisioning 403, unavailable execution 503. Requests and responses
must not be cached or redirected. Tuist scopes the durable mapping by account and
SHA-256 of `[issuer, subject, environment_id]`; clients never choose a VM ID.

Before production enrollment, smoke-test real VM start, public clone/file read,
terminal completion, pause/resume and deletion with an authorized pilot identity.
Local adapter tests and fixture screenshots do not establish fleet connectivity.
