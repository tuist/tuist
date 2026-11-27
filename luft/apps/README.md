# Portable Luft Apps

A Luft App is a versioned, organization-neutral package of models, queries,
actions, fixtures and optional native UI modules. A workspace installs apps into one
organization's PostgreSQL business database. Apps are not separate binaries or
databases, and a domain can expose several modules inside Luft's host navigation.

This is a local pilot contract, not a public distribution format. These two apps
exercise it before a hosted directory, signatures, installation approvals or
production authorization are built.

## Capabilities first, presentation optional

An app can declare `"ui_modules": []` and contain no UI source. Its models,
references, fixtures, queries and actions still publish normally. This already
works in the definition loader; the MCP integration test deletes both apps' UI
bundles before publishing and executing their contracts.

The local preview API exposes those contracts at `/mcp` using stateless MCP
Streamable HTTP (2025-03-26), independently of the selected native module.
Queries are offered by default; action tools require explicit host-side grants.
Tool input schemas come from the published models, including UUID references,
enums, optional/defaulted fields and revision checks. Mutations use the same
PostgreSQL validation, request replay results and audit as the native UI.

Conversation history is not authoritative business state. A returned record is a
snapshot of a revision; read again for current data, and send an explicit desired
value with the revision when updating. Obtain a submission UUID from
`workspace_request_id` once and retain it with the exact input for an uncertain
retry. Do not regenerate the UUID just because a response was lost. A revision
conflict needs a fresh read and decision, not an automatic overwrite.

Keep persistent destinations for browsing and recurring queues. Do not require
model inference for deterministic navigation or known-record actions. The local
MCP endpoint remains separate from authenticated Threads. The opt-in Thread
integration instead supplies authorized query discovery and a `show_record` tool
that persists only `{model,id}`. Readers open that message through their normal
Luft credentials; the server rechecks their own thread access and explicit user
query/action grants on each request. It does not inherit the author's permissions.
See the [server installation/grant contract](../../luft-server/README.md#opt-in-thread-record-references).

Native hosts pass an authorized `entry: {model,id}`, canonical `record` and filtered
`capabilities` in module launch parameters. Accounts and Support can start directly
on that record, without fetching a list. The native host owns the return to the
session; linked-record pages use the module's native navigation stack. Hiding
buttons follows capabilities but is not authorization; the server checks calls.
The simulator's original fixture-backed Support handoff remains available as a
separate local harness. Neither path interprets prose or generated card JavaScript
as a privileged record link. Existing cards retain their reply-only bridge.
See the [local agent connection guide](../workspaces/customer-management/README.md#use-the-same-contracts-from-a-local-agent).

## Package and installation

`customer-management/app.json` declares stable ID `accounts`, version 1, model
`accounts.customer` and the Customers module. `support/app.json` declares ID
`support`, version 1, model `support.conversation` and Inbox. Support depends on
exactly `accounts: 1`. Its customer field is:

```json
{"type":"reference","model":"accounts.customer","nullable":true}
```

The organization belongs only in the installation workspace:

```json
{
  "format": 1,
  "organization": "demo",
  "title": "Company workspace",
  "apps": [
    "../../apps/customer-management/app.json",
    "../../apps/support/app.json"
  ]
}
```

Move/copy both package directories and change workspace-relative app paths to
install elsewhere. No organization IDs, absolute paths, database names, tokens or
server origins belong in an app. UI bundles and fixture paths resolve inside each
app directory; Support does not import Accounts source. Definitions and UI module
IDs must belong to their app namespace. Duplicate IDs, missing or mismatched
dependencies and undeclared cross-app contracts fail publication.

An app version pins a package dependency; each model also has its own migration
version. The pilot rejects invalid/destructive model evolution and supports
additive fields with explicit model-version increments. It does not yet enforce
immutable app-version content hashes, independent install/uninstall, automatic
dependency downloads or upgrade compatibility across multiple active versions.
Publication currently composes the whole workspace atomically.

## Cross-app data and native pages

The organization database installs both tables and a real UUID foreign key.
Fixtures are merged and seeded transactionally, independent of package ordering.
References restrict target deletion; no deletion API is offered. A bad reference
cannot leave a record, audit entry or replay result behind.

A reference grants no implicit read or write access. Inbox explicitly declares
`accounts.customer.get`, which accepts `{id}` and returns `{record}`. The Rust
client permits the getter because the selected model declares that target
reference and the module declares the capability. It rejects customer writes.
This is module-capability enforcement, **not actor-level authorization**: the
local preview token grants access to its whole disposable database.

Inbox navigates through native pages: conversation list, conversation detail,
read-only customer detail. Fetching a customer leaves the inbox records and
native history intact. Each app owns its presentation; this is not yet a global
route that launches the target app. A future directory needs exported route
contracts and runtime compatibility in addition to package dependencies.

## Build and test

From `luft/`, using NSH 0.5.1 (`NSH_BIN` may override its path):

```sh
bash apps/customer-management/ui/build.sh
bash apps/support/ui/build.sh
cargo test -p tuist-app-core --locked
```

Each build script runs its app's headless UI tests and rebuilds `ui/bundle.js`.
Commit TSX and its generated source bundle together. Only source is published;
remote bytecode is not loaded. Headless navigation checks do not establish iOS
layout, system gestures or physical-device behavior.

Follow the [workspace guide](../workspaces/customer-management/README.md) to
publish, seed and serve locally and opt into Luft's simulator-only preview.
Publishing never implicitly loads fixture records. Rehearsal credentials do not
enter JS or production identity storage.

## Directory direction

Build a directory around this package boundary rather than sharing an entire
organization workspace. Before third-party distribution, add publisher-qualified
identities, immutable content hashes, signed provenance, supported host/runtime
versions and platforms, explicit export contracts, dependency resolution, review
of requested capabilities, safe upgrade/uninstall plans and organization-specific
installation grants. Do not mistake this local loader for those protections.
